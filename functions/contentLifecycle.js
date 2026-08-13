"use strict";

const FREE_ACCESSIBLE_MONTHS = 2;
const FREE_DELETION_GRACE_MONTHS = 1;

function subtractCalendarMonths(date, months) {
  const result = new Date(date.getTime());
  const originalDay = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() - months);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(originalDay, lastDay));
  return result;
}

function hasPremiumRetention(entitlement, now = new Date()) {
  if (!entitlement || entitlement.membershipTier !== "premium") return false;
  if (!["active", "gracePeriod"].includes(entitlement.premiumStatus)) return false;
  if (!entitlement.premiumExpirationDate) return true;
  const expires = entitlement.premiumExpirationDate.toDate
    ? entitlement.premiumExpirationDate.toDate()
    : new Date(entitlement.premiumExpirationDate);
  return expires.getTime() > now.getTime() || entitlement.premiumStatus === "gracePeriod";
}

function retentionDecision({ issueDate, entitlement, now = new Date() }) {
  if (hasPremiumRetention(entitlement, now)) {
    return { state: "accessible", reason: "premium_active", deleteEligible: false };
  }
  const lockBefore = subtractCalendarMonths(now, FREE_ACCESSIBLE_MONTHS);
  const deleteBefore = subtractCalendarMonths(now, FREE_ACCESSIBLE_MONTHS + FREE_DELETION_GRACE_MONTHS);
  if (issueDate.getTime() < deleteBefore.getTime()) {
    return { state: "locked", reason: "free_grace_elapsed", deleteEligible: true };
  }
  if (issueDate.getTime() < lockBefore.getTime()) {
    return { state: "locked", reason: "free_archive_window_elapsed", deleteEligible: false };
  }
  return { state: "accessible", reason: "within_free_archive_window", deleteEligible: false };
}

async function deletePrefix(bucket, prefix, logger = console) {
  const [files] = await bucket.getFiles({ prefix });
  if (files.length === 0) return [];
  const paths = files.map((file) => file.name);
  await Promise.all(files.map(async (file) => {
    try {
      await file.delete({ ignoreNotFound: true });
    } catch (error) {
      logger.error("STORAGE_DELETE_FAILED", { path: file.name, error: error.message });
      throw error;
    }
  }));
  return paths;
}

async function deleteIssueStorage(bucket, issueID, logger = console) {
  return deletePrefix(bucket, `publishedIssues/${issueID}/`, logger);
}

async function deleteDraftStorage(bucket, ownerID, draftID, logger = console) {
  return deletePrefix(bucket, `issueDrafts/${ownerID}/${draftID}/`, logger);
}

async function deleteAccountOwnedStorage(bucket, ownerID, draftIDs, issueIDs, logger = console) {
  return Promise.all([
    ...draftIDs.map((draftID) => deleteDraftStorage(bucket, ownerID, draftID, logger)),
    ...issueIDs.map((issueID) => deleteIssueStorage(bucket, issueID, logger)),
    deletePrefix(bucket, `users/${ownerID}/`, logger),
  ]);
}

async function runRetention({ db, bucket, logger = console, now = new Date(), deletionEnabled = false }) {
  const issues = await db.collection("publishedIssues").get();
  const entitlementCache = new Map();
  const report = [];

  for (const doc of issues.docs) {
    const issue = doc.data() || {};
    const ownerID = issue.ownerID || "";
    const issueDate = issue.createdAt && issue.createdAt.toDate ? issue.createdAt.toDate() : null;
    if (!ownerID || !issueDate) continue;

    if (!entitlementCache.has(ownerID)) {
      const entitlementSnap = await db.collection("users").doc(ownerID)
        .collection("privateEntitlements").doc("current").get();
      entitlementCache.set(ownerID, entitlementSnap.exists ? entitlementSnap.data() : {});
    }
    const entitlement = entitlementCache.get(ownerID);
    if (!Array.isArray(issue.authorizedReaderIDs)) {
      const readers = new Set([ownerID]);
      for (const groupID of issue.groupIDs || []) {
        const groupSnap = await db.collection("groups").doc(groupID).get();
        if (groupSnap.exists) (groupSnap.data().memberIDs || []).forEach((uid) => readers.add(uid));
      }
      await doc.ref.set({ authorizedReaderIDs: Array.from(readers) }, { merge: true });
    }
    const decision = retentionDecision({ issueDate, entitlement, now });
    const candidate = {
      user: ownerID,
      issueID: doc.id,
      issueDate: issueDate.toISOString(),
      entitlement: hasPremiumRetention(entitlement, now) ? "premium" : "free",
      founder: entitlement.isFounderSupporter === true,
      reason: decision.reason,
      deleteEligible: decision.deleteEligible,
      storagePrefixes: [`publishedIssues/${doc.id}/`],
    };
    report.push(candidate);
    logger.info("RETENTION_CANDIDATE", candidate);

    if (decision.state === "locked" && issue.retentionState !== "locked") {
      await doc.ref.set({
        retentionState: "locked",
        retentionLockedAt: now,
        retentionReason: decision.reason,
      }, { merge: true });
      await db.collection("users").doc(ownerID).set({
        archiveRetentionNotice: {
          issueID: doc.id,
          lockedAt: now,
          permanentDeletionPossible: true,
          messageVersion: 1,
        },
      }, { merge: true });
    } else if (decision.state === "accessible" && issue.retentionState === "locked") {
      await doc.ref.set({ retentionState: "accessible" }, { merge: true });
    }

    if (decision.deleteEligible && deletionEnabled) {
      // Storage is removed first. The metadata delete is last so retries remain discoverable.
      await deleteIssueStorage(bucket, doc.id, logger);
      await doc.ref.delete();
      logger.info("RETENTION_DELETED", candidate);
    }
  }
  return report;
}

module.exports = {
  FREE_ACCESSIBLE_MONTHS,
  FREE_DELETION_GRACE_MONTHS,
  subtractCalendarMonths,
  hasPremiumRetention,
  retentionDecision,
  deletePrefix,
  deleteIssueStorage,
  deleteDraftStorage,
  deleteAccountOwnedStorage,
  runRetention,
};
