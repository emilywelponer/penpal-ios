const { onDocumentCreated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {
  AppStoreServerAPIClient,
  Environment,
  GetTransactionHistoryVersion,
  InAppOwnershipType,
  Order,
  ProductType,
  SignedDataVerifier,
} = require("@apple/app-store-server-library");

admin.initializeApp();

const db = admin.firestore();

const BUNDLE_ID = "com.emily.penpal";
const FOUNDER_PRODUCT_ID = "com.emily.penpal.founder";
const PREMIUM_MONTHLY_PRODUCT_ID = "com.emily.penpal.premium.monthly";
const PREMIUM_ANNUAL_PRODUCT_ID = "com.emily.penpal.premium.annual";
const ALLOWED_PRODUCT_IDS = new Set([
  FOUNDER_PRODUCT_ID,
  PREMIUM_MONTHLY_PRODUCT_ID,
  PREMIUM_ANNUAL_PRODUCT_ID,
]);
const PREMIUM_PRODUCT_IDS = new Set([
  PREMIUM_MONTHLY_PRODUCT_ID,
  PREMIUM_ANNUAL_PRODUCT_ID,
]);
const APPLE_SECRETS = [
  defineSecret("APPLE_ISSUER_ID"),
  defineSecret("APPLE_KEY_ID"),
  defineSecret("APPLE_PRIVATE_KEY"),
  defineSecret("APPLE_APP_APPLE_ID"),
  defineSecret("APPLE_ROOT_CERTIFICATES_BASE64_JSON"),
  defineSecret("APPLE_ENVIRONMENT"),
];

exports.getOrCreateAppAccountToken = onCall(async (request) => {
  const uid = requireAuth(request);
  const entitlementRef = privateEntitlementRef(uid);
  const tokenRefRoot = db.collection("appAccountTokens");

  const appAccountToken = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(entitlementRef);
    const existingToken = snap.exists ? snap.data().appAccountToken : null;

    if (typeof existingToken === "string" && existingToken.length > 0) {
      return existingToken;
    }

    const token = crypto.randomUUID();
    transaction.set(entitlementRef, {
      schemaVersion: 1,
      membershipTier: "free",
      isFounderSupporter: false,
      appAccountToken: token,
      premiumProductID: null,
      premiumOriginalTransactionID: null,
      premiumLatestTransactionID: null,
      premiumExpirationDate: null,
      premiumWillRenew: null,
      premiumStatus: "none",
      premiumInGracePeriod: false,
      premiumInBillingRetry: false,
      founderOriginalTransactionID: null,
      founderLatestTransactionID: null,
      founderPurchasedAt: null,
      environment: null,
      lastVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(tokenRefRoot.doc(token), {
      uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return token;
  });

  return { appAccountToken };
});

exports.processAppStoreTransaction = onCall({ secrets: APPLE_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const signedTransactionInfo = request.data && request.data.signedTransactionInfo;

  if (typeof signedTransactionInfo !== "string" || signedTransactionInfo.length < 20) {
    throw new HttpsError("invalid-argument", "Missing signed transaction.");
  }

  const verified = await verifySignedTransaction(signedTransactionInfo);
  await processVerifiedTransactionForUID({
    uid,
    decodedTransaction: verified.decodedTransaction,
    signedTransactionInfo,
    signedRenewalInfo: null,
    notificationType: "CLIENT_PURCHASE",
    environment: verified.environmentName,
    allowCreateBinding: true,
  });

  return {
    ok: true,
    productID: verified.decodedTransaction.productId || verified.decodedTransaction.productID,
  };
});

exports.reconcileAppStoreEntitlements = onCall({ secrets: APPLE_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const entitlementSnap = await privateEntitlementRef(uid).get();
  if (!entitlementSnap.exists) {
    return { ok: true, reconciledTransactions: 0 };
  }

  const entitlement = entitlementSnap.data() || {};
  const originalIDs = [
    entitlement.premiumOriginalTransactionID,
    entitlement.founderOriginalTransactionID,
  ].filter((value) => typeof value === "string" && value.length > 0);

  let reconciledTransactions = 0;
  for (const originalTransactionID of new Set(originalIDs)) {
    reconciledTransactions += await reconcileOriginalTransactionForUID(uid, originalTransactionID);
  }

  return { ok: true, reconciledTransactions };
});

exports.appStoreServerNotificationsV2 = onRequest({ secrets: APPLE_SECRETS }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const signedPayload = req.body && req.body.signedPayload;
  if (typeof signedPayload !== "string" || signedPayload.length < 20) {
    res.status(400).send("Missing signedPayload");
    return;
  }

  try {
    const verified = await verifySignedNotification(signedPayload);
    const notification = verified.decodedNotification || {};
    const notificationUUID = notification.notificationUUID;
    if (!notificationUUID) {
      res.status(400).send("Missing notificationUUID");
      return;
    }

    const eventRef = db.collection("appStoreNotificationEvents").doc(notificationUUID);
    const claimed = await claimAppStoreNotificationEvent(eventRef, notification);
    if (!claimed) {
      res.status(200).send("duplicate");
      return;
    }

    const signedTransactionInfo = notification.data && notification.data.signedTransactionInfo;
    const signedRenewalInfo = notification.data && notification.data.signedRenewalInfo;
    if (typeof signedTransactionInfo !== "string") {
      await eventRef.set({
        status: "skipped",
        reason: "missing_transaction_info",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      res.status(200).send("skipped");
      return;
    }

    const transactionVerification = await verifySignedTransaction(signedTransactionInfo);
    const decodedTransaction = transactionVerification.decodedTransaction;
    const originalTransactionID = normalizedOriginalTransactionID(decodedTransaction);
    const bindingSnap = await db.collection("appStoreOriginalTransactions").doc(originalTransactionID).get();
    const uid = bindingSnap.exists ? bindingSnap.data().uid : await uidForAppAccountToken(decodedTransaction.appAccountToken);

    if (!uid) {
      await eventRef.set({
        status: "failed",
        reason: "unknown_account_binding",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      res.status(202).send("unknown account");
      return;
    }

    await processVerifiedTransactionForUID({
      uid,
      decodedTransaction,
      signedTransactionInfo,
      signedRenewalInfo,
      notificationType: notification.notificationType || "UNKNOWN",
      notificationSubtype: notification.subtype || null,
      environment: transactionVerification.environmentName,
      allowCreateBinding: false,
    });

    await eventRef.set({
      status: "processed",
      uid,
      originalTransactionID,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    res.status(200).send("ok");
  } catch (error) {
    logger.error("APP_STORE_NOTIFICATION_FAILED", { error: error && error.message });
    res.status(400).send("verification failed");
  }
});

exports.notifyPublishedIssue = onDocumentCreated("publishedIssues/{issueID}", async (event) => {
  const issue = event.data && event.data.data();
  if (!issue) {
    return;
  }

  const issueID = event.params.issueID;
  const publisherID = issue.ownerID || issue.publisherID;
  const groupIDs = Array.isArray(issue.groupIDs) ? issue.groupIDs : (issue.groupID ? [issue.groupID] : []);
  const month = issue.month || "";
  const year = issue.year || "";

  if (!publisherID || groupIDs.length === 0) {
    logger.warn("PUSH_SKIP_MISSING_FIELDS", { issueID, publisherID, groupIDs });
    return;
  }

  const publisherName = await displayNameForUser(publisherID);

  for (const groupID of groupIDs) {
    const groupSnap = await db.collection("groups").doc(groupID).get();
    if (!groupSnap.exists) {
      logger.warn("PUSH_SKIP_MISSING_GROUP", { issueID, groupID });
      continue;
    }

    const group = groupSnap.data() || {};
    const groupName = group.name || "your group";
    const memberIDs = Array.isArray(group.memberIDs) ? group.memberIDs : [];
    const recipients = memberIDs.filter((uid) => uid && uid !== publisherID);

    await sendToUsers(recipients, (languageRaw) => {
      const copy = localizedPushCopy(languageRaw);
      return {
        notification: {
          title: copy.newIssueTitle,
          body: copy.newIssueBody(publisherName, month, groupName),
        },
      data: {
        type: "newIssue",
        issueID,
        groupID,
        month: String(month),
        year: String(year),
      },
      };
    }, "PUSH_NEW_ISSUE_SENT", { issueID, groupID });

    await maybeSendGoldenHeart({ groupID, groupName, memberIDs, month, year });
  }
});

exports.notifyMarginNotePublished = onDocumentCreated("MarginNotes/{noteID}", async (event) => {
  const note = event.data && event.data.data();
  if (!note) {
    return;
  }

  const noteID = event.params.noteID;
  const magazineID = typeof note.magazineID === "string" ? note.magazineID : "";
  const noteAuthorID = typeof note.authorID === "string" ? note.authorID : "";
  const pageIndex = Number.isInteger(note.pageIndex) ? note.pageIndex : null;
  const text = typeof note.text === "string" ? note.text.trim() : "";

  if (!magazineID || !noteAuthorID || text.length === 0) {
    await writeNotificationEventStatus({
      eventID: `marginNote_${noteID}`,
      type: "margin_note_published",
      marginNoteID: noteID,
      magazineID,
      recipientUserID: "",
      status: "skipped",
      reason: "missing_required_fields",
    });
    return;
  }

  const issueSnap = await db.collection("publishedIssues").doc(magazineID).get();
  if (!issueSnap.exists) {
    await writeNotificationEventStatus({
      eventID: `marginNote_${noteID}`,
      type: "margin_note_published",
      marginNoteID: noteID,
      magazineID,
      recipientUserID: "",
      status: "skipped",
      reason: "missing_magazine",
    });
    return;
  }

  const issue = issueSnap.data() || {};
  const magazineOwnerID = issue.ownerID || "";
  if (!magazineOwnerID || magazineOwnerID === noteAuthorID) {
    await writeNotificationEventStatus({
      eventID: `marginNote_${noteID}`,
      type: "margin_note_published",
      marginNoteID: noteID,
      magazineID,
      recipientUserID: magazineOwnerID,
      status: "skipped",
      reason: magazineOwnerID === noteAuthorID ? "own_magazine" : "missing_owner",
    });
    return;
  }

  const ownerSnap = await db.collection("users").doc(magazineOwnerID).get();
  const owner = ownerSnap.exists ? (ownerSnap.data() || {}) : {};
  if (owner.marginNoteNotificationsEnabled === false) {
    await writeNotificationEventStatus({
      eventID: `marginNote_${noteID}`,
      type: "margin_note_published",
      marginNoteID: noteID,
      magazineID,
      recipientUserID: magazineOwnerID,
      status: "skipped",
      reason: "recipient_disabled",
    });
    return;
  }

  const eventID = `marginNote_${noteID}`;
  const eventRef = db.collection("notificationEvents").doc(eventID);
  const claimed = await claimNotificationEvent(eventRef, {
    type: "margin_note_published",
    marginNoteID: noteID,
    magazineID,
    recipientUserID: magazineOwnerID,
  });

  if (!claimed) {
    logger.info("PUSH_MARGIN_NOTE_EVENT_ALREADY_HANDLED", { marginNoteID: noteID, magazineID });
    return;
  }

  try {
    const displayName = note.authorDisplayName || note.authorUsername || await displayNameForUser(noteAuthorID);
    const delivery = await sendToUsers([magazineOwnerID], (languageRaw) => {
      const copy = localizedPushCopy(languageRaw);
      return {
        notification: {
          title: copy.marginNoteTitle,
          body: copy.marginNoteBody(displayName),
        },
        data: {
          type: "margin_note_published",
          magazineID,
          marginNoteID: noteID,
          pageIndex: pageIndex === null ? "" : String(pageIndex),
        },
        android: {
          notification: {
            channelId: "margin_notes",
          },
        },
        apns: {
          headers: {
            "apns-collapse-id": `marginNote_${noteID}`,
          },
          payload: {
            aps: {
              category: "MARGIN_NOTE_PUBLISHED",
            },
          },
        },
      };
    }, "PUSH_MARGIN_NOTE_SENT", { marginNoteID: noteID, magazineID });

    if (delivery.successCount > 0) {
      await eventRef.set({
        status: "sent",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        tokenCount: delivery.tokenCount,
        successCount: delivery.successCount,
        failureCount: delivery.failureCount,
      }, { merge: true });
      return;
    }

    const status = delivery.tokenCount === 0 ? "skipped" : "failed";
    await eventRef.set({
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      tokenCount: delivery.tokenCount,
      successCount: delivery.successCount,
      failureCount: delivery.failureCount,
      failureReason: delivery.tokenCount === 0 ? "no_tokens" : "send_failed",
    }, { merge: true });
  } catch (error) {
    await eventRef.set({
      status: "failed",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      failureReason: error && error.message ? error.message : "unknown",
    }, { merge: true });
    logger.error("PUSH_MARGIN_NOTE_FAILED", {
      marginNoteID: noteID,
      magazineID,
      error: error && error.message,
    });
  }
});

// MARK: PenPal Lab Feature

exports.updatePenPalLabVoteCountOnCreate = onDocumentCreated(
  "penpalLabSuggestions/{suggestionID}/votes/{userID}",
  async (event) => {
    const vote = event.data && event.data.data();
    const { suggestionID, userID } = event.params;
    if (!vote || vote.userID !== userID) {
      logger.warn("PENPAL_LAB_VOTE_CREATE_SKIP", { suggestionID, userID });
      return;
    }

    await updatePenPalLabVoteCount(suggestionID);
  }
);

exports.updatePenPalLabVoteCountOnDelete = onDocumentDeleted(
  "penpalLabSuggestions/{suggestionID}/votes/{userID}",
  async (event) => {
    const { suggestionID, userID } = event.params;
    logger.info("PENPAL_LAB_VOTE_REMOVED", { suggestionID, userID });
    await updatePenPalLabVoteCount(suggestionID);
  }
);

async function updatePenPalLabVoteCount(suggestionID) {
  const suggestionRef = db.collection("penpalLabSuggestions").doc(suggestionID);
  const suggestionSnap = await suggestionRef.get();
  if (!suggestionSnap.exists) {
    return;
  }

  const countSnap = await suggestionRef.collection("votes").count().get();
  const voteCount = Math.max(0, countSnap.data().count || 0);
  await suggestionRef.update({
    voteCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function claimNotificationEvent(eventRef, data) {
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(eventRef);
    const now = Date.now();

    if (snap.exists) {
      const current = snap.data() || {};
      if (current.status === "sent" || current.status === "skipped") {
        return false;
      }

      if (current.status === "processing") {
        const updatedAt = current.updatedAt && current.updatedAt.toMillis ? current.updatedAt.toMillis() : 0;
        const processingIsFresh = updatedAt > now - (10 * 60 * 1000);
        if (processingIsFresh) {
          return false;
        }
      }
    }

    transaction.set(eventRef, {
      ...data,
      status: "processing",
      createdAt: snap.exists ? snap.data().createdAt || admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return true;
  });
}

async function writeNotificationEventStatus({ eventID, type, marginNoteID, magazineID, recipientUserID, status, reason }) {
  const eventRef = db.collection("notificationEvents").doc(eventID);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(eventRef);
    if (snap.exists) {
      const currentStatus = (snap.data() || {}).status;
      if (currentStatus === "sent" || currentStatus === "skipped") {
        return;
      }
    }

    transaction.set(eventRef, {
      type,
      marginNoteID,
      magazineID,
      recipientUserID,
      status,
      reason,
      createdAt: snap.exists ? snap.data().createdAt || admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function maybeSendGoldenHeart({ groupID, groupName, memberIDs, month, year }) {
  if (!month || !year || memberIDs.length === 0) {
    return;
  }

  const monthKey = `${year}-${month}`;
  const markerRef = db.collection("groups").doc(groupID).collection("goldenHeartMonths").doc(monthKey);

  const shouldNotify = await db.runTransaction(async (transaction) => {
    const marker = await transaction.get(markerRef);
    if (marker.exists && marker.data().goldenHeartNotified === true) {
      return false;
    }

    const issues = await db.collection("publishedIssues")
      .where("groupIDs", "array-contains", groupID)
      .where("month", "==", month)
      .where("year", "==", year)
      .get();

    const posted = new Set();
    issues.forEach((doc) => {
      const ownerID = doc.data().ownerID || doc.data().publisherID;
      if (ownerID) {
        posted.add(ownerID);
      }
    });

    const everyonePosted = memberIDs.every((uid) => posted.has(uid));
    if (!everyonePosted) {
      return false;
    }

    transaction.set(markerRef, {
      goldenHeartNotified: true,
      month,
      year,
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return true;
  });

  if (!shouldNotify) {
    return;
  }

  await sendToUsers(memberIDs, (languageRaw) => {
    const copy = localizedPushCopy(languageRaw);
    return {
      notification: {
        title: copy.goldenHeartTitle,
        body: copy.goldenHeartBody(groupName),
      },
    data: {
      type: "goldenHeart",
      groupID,
      month: String(month),
      year: String(year),
    },
    };
  }, "PUSH_GOLD_HEART_SENT", { groupID, month, year });
}

async function displayNameForUser(uid) {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    return "Someone";
  }

  const user = userSnap.data() || {};
  return user.displayName || user.username || "Someone";
}

async function sendToUsers(userIDs, payloadForLanguage, logLabel, logData) {
  const tokenRecords = await tokensForUsers(userIDs);
  if (tokenRecords.length === 0) {
    logger.info(logLabel, { ...logData, tokenCount: 0 });
    return {
      tokenCount: 0,
      successCount: 0,
      failureCount: 0,
    };
  }

  let successCount = 0;
  let failureCount = 0;

  const badgeCounts = new Map();
  await Promise.all(userIDs.map(async (uid) => {
    badgeCounts.set(uid, await unreadGroupIssueCount(uid));
  }));

  const messages = tokenRecords.map(({ token, userID, languageRaw }) => {
    const payload = payloadForLanguage(languageRaw);
    const baseApns = payload.apns || {};
    const baseAps = baseApns.payload && baseApns.payload.aps ? baseApns.payload.aps : {};
    return {
      token,
      notification: payload.notification,
      data: payload.data,
      android: payload.android,
      apns: {
        ...baseApns,
        payload: {
          ...(baseApns.payload || {}),
          aps: {
            ...baseAps,
            sound: "default",
            badge: badgeCounts.get(userID) || 0,
          },
        },
      },
    };
  });

  const response = await admin.messaging().sendEach(messages);
  successCount += response.successCount;
  failureCount += response.failureCount;

  response.responses.forEach((result, index) => {
    if (!result.success) {
      const tokenRecord = tokenRecords[index];
      logger.warn("PUSH_SEND_TOKEN_ERROR", {
        ...logData,
        userID: tokenRecord.userID,
        error: result.error && result.error.message,
      });
      if (isInvalidTokenError(result.error)) {
        removeInvalidToken(tokenRecord).catch((error) => {
          logger.warn("PUSH_REMOVE_INVALID_TOKEN_ERROR", {
            userID: tokenRecord.userID,
            error: error && error.message,
          });
        });
      }
    }
  });

  logger.info(logLabel, {
    ...logData,
    tokenCount: tokenRecords.length,
    successCount,
    failureCount,
  });

  return {
    tokenCount: tokenRecords.length,
    successCount,
    failureCount,
  };
}

function isInvalidTokenError(error) {
  const code = error && error.code;
  return code === "messaging/registration-token-not-registered"
    || code === "messaging/invalid-registration-token"
    || code === "messaging/invalid-argument";
}

async function removeInvalidToken({ userID, token }) {
  if (!userID || !token) {
    return;
  }

  await db.collection("users")
    .doc(userID)
    .collection("fcmTokens")
    .doc(token)
    .delete();
}

async function unreadGroupIssueCount(uid) {
  const groupSnap = await db.collection("groups")
    .where("memberIDs", "array-contains", uid)
    .get();

  const unreadIssueIDs = new Set();

  for (const groupDoc of groupSnap.docs) {
    const issueSnap = await db.collection("publishedIssues")
      .where("groupIDs", "array-contains", groupDoc.id)
      .get();

    issueSnap.forEach((doc) => {
      const issue = doc.data() || {};
      const viewedBy = Array.isArray(issue.viewedBy) ? issue.viewedBy : [];
      if (!viewedBy.includes(uid)) {
        unreadIssueIDs.add(doc.id);
      }
    });
  }

  return unreadIssueIDs.size;
}

async function tokensForUsers(userIDs) {
  const byToken = new Map();

  await Promise.all(userIDs.map(async (uid) => {
    const tokenSnap = await db.collection("users").doc(uid).collection("fcmTokens").get();
    tokenSnap.forEach((doc) => {
      if (doc.id) {
        byToken.set(doc.id, {
          token: doc.id,
          userID: uid,
          languageRaw: doc.data().languageRaw || "English",
        });
      }
    });
  }));

  return Array.from(byToken.values());
}

function requireAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You need to be signed in.");
  }
  return uid;
}

function privateEntitlementRef(uid) {
  return db.collection("users")
    .doc(uid)
    .collection("privateEntitlements")
    .doc("current");
}

function configuredAppleEnvironment() {
  const raw = (process.env.APPLE_ENVIRONMENT || "Production").toLowerCase();
  return raw === "sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
}

function configuredAppleEnvironmentName(environment) {
  return environment === Environment.SANDBOX ? "Sandbox" : "Production";
}

function appAppleIDForEnvironment(environment) {
  if (environment === Environment.PRODUCTION) {
    const appAppleID = Number(process.env.APPLE_APP_APPLE_ID);
    if (!Number.isInteger(appAppleID) || appAppleID <= 0) {
      throw new Error("APPLE_APP_APPLE_ID is required for Production verification.");
    }
    return appAppleID;
  }
  return undefined;
}

function appleRootCertificates() {
  const raw = process.env.APPLE_ROOT_CERTIFICATES_BASE64_JSON;
  if (!raw) {
    throw new Error("APPLE_ROOT_CERTIFICATES_BASE64_JSON is required.");
  }

  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error("APPLE_ROOT_CERTIFICATES_BASE64_JSON must be a non-empty JSON array.");
  }

  return parsed.map((entry) => Buffer.from(entry, "base64"));
}

function appleVerifier(environment = configuredAppleEnvironment()) {
  return new SignedDataVerifier(
    appleRootCertificates(),
    true,
    environment,
    BUNDLE_ID,
    appAppleIDForEnvironment(environment)
  );
}

function appStoreClient(environment = configuredAppleEnvironment()) {
  const issuerID = process.env.APPLE_ISSUER_ID;
  const keyID = process.env.APPLE_KEY_ID;
  const privateKey = process.env.APPLE_PRIVATE_KEY;
  if (!issuerID || !keyID || !privateKey) {
    throw new Error("Apple App Store Server API credentials are missing.");
  }

  return new AppStoreServerAPIClient(privateKey, keyID, issuerID, BUNDLE_ID, environment);
}

async function verifySignedTransaction(signedTransactionInfo) {
  const preferredEnvironment = configuredAppleEnvironment();
  const fallbackEnvironment = preferredEnvironment === Environment.PRODUCTION
    ? Environment.SANDBOX
    : Environment.PRODUCTION;

  try {
    const decodedTransaction = await appleVerifier(preferredEnvironment).verifyAndDecodeTransaction(signedTransactionInfo);
    validateDecodedTransaction(decodedTransaction);
    return {
      decodedTransaction,
      environment: preferredEnvironment,
      environmentName: configuredAppleEnvironmentName(preferredEnvironment),
    };
  } catch (primaryError) {
    try {
      const decodedTransaction = await appleVerifier(fallbackEnvironment).verifyAndDecodeTransaction(signedTransactionInfo);
      validateDecodedTransaction(decodedTransaction);
      return {
        decodedTransaction,
        environment: fallbackEnvironment,
        environmentName: configuredAppleEnvironmentName(fallbackEnvironment),
      };
    } catch (fallbackError) {
      throw primaryError;
    }
  }
}

async function verifySignedNotification(signedPayload) {
  const preferredEnvironment = configuredAppleEnvironment();
  const fallbackEnvironment = preferredEnvironment === Environment.PRODUCTION
    ? Environment.SANDBOX
    : Environment.PRODUCTION;

  try {
    const decodedNotification = await appleVerifier(preferredEnvironment).verifyAndDecodeNotification(signedPayload);
    return {
      decodedNotification,
      environment: preferredEnvironment,
      environmentName: configuredAppleEnvironmentName(preferredEnvironment),
    };
  } catch (primaryError) {
    try {
      const decodedNotification = await appleVerifier(fallbackEnvironment).verifyAndDecodeNotification(signedPayload);
      return {
        decodedNotification,
        environment: fallbackEnvironment,
        environmentName: configuredAppleEnvironmentName(fallbackEnvironment),
      };
    } catch (fallbackError) {
      throw primaryError;
    }
  }
}

function validateDecodedTransaction(decodedTransaction) {
  const productID = normalizedProductID(decodedTransaction);
  if (!ALLOWED_PRODUCT_IDS.has(productID)) {
    throw new HttpsError("failed-precondition", "Unknown App Store product.");
  }

  if (decodedTransaction.bundleId && decodedTransaction.bundleId !== BUNDLE_ID) {
    throw new HttpsError("failed-precondition", "Transaction bundle identifier does not match PenPal.");
  }

  if (!normalizedTransactionID(decodedTransaction) || !normalizedOriginalTransactionID(decodedTransaction)) {
    throw new HttpsError("failed-precondition", "Transaction is missing required identifiers.");
  }

  if (decodedTransaction.inAppOwnershipType && decodedTransaction.inAppOwnershipType !== InAppOwnershipType.PURCHASED) {
    throw new HttpsError("failed-precondition", "Unsupported App Store ownership type.");
  }
}

async function processVerifiedTransactionForUID({
  uid,
  decodedTransaction,
  signedTransactionInfo,
  signedRenewalInfo,
  notificationType,
  notificationSubtype = null,
  environment,
  allowCreateBinding,
}) {
  const productID = normalizedProductID(decodedTransaction);
  const transactionID = normalizedTransactionID(decodedTransaction);
  const originalTransactionID = normalizedOriginalTransactionID(decodedTransaction);
  const appAccountToken = decodedTransaction.appAccountToken;
  if (!appAccountToken) {
    throw new HttpsError("failed-precondition", "Transaction is missing appAccountToken.");
  }

  await db.runTransaction(async (transaction) => {
    const entitlementRef = privateEntitlementRef(uid);
    const entitlementSnap = await transaction.get(entitlementRef);
    const entitlement = entitlementSnap.exists ? entitlementSnap.data() : {};

    if (entitlement.appAccountToken !== appAccountToken) {
      throw new HttpsError("permission-denied", "Transaction account token does not belong to this PenPal account.");
    }

    const originalRef = db.collection("appStoreOriginalTransactions").doc(originalTransactionID);
    const originalSnap = await transaction.get(originalRef);
    if (originalSnap.exists && originalSnap.data().uid !== uid) {
      throw new HttpsError("already-exists", "This Apple purchase is already linked to another PenPal account.");
    }

    if (!originalSnap.exists && !allowCreateBinding) {
      throw new HttpsError("failed-precondition", "Transaction binding does not exist.");
    }

    const transactionRef = db.collection("appStoreTransactions").doc(transactionID);
    const transactionSnap = await transaction.get(transactionRef);
    if (transactionSnap.exists && transactionSnap.data().uid !== uid) {
      throw new HttpsError("already-exists", "This Apple transaction is already linked to another PenPal account.");
    }

    const nextEntitlement = deriveEntitlementUpdate(entitlement, decodedTransaction, environment);

    transaction.set(originalRef, {
      uid,
      originalTransactionID,
      productKind: PREMIUM_PRODUCT_IDS.has(productID) ? "premium" : "founderSupporter",
      appAccountToken,
      environment,
      createdAt: originalSnap.exists
        ? originalSnap.data().createdAt || admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    transaction.set(transactionRef, {
      uid,
      transactionID,
      originalTransactionID,
      productID,
      environment,
      notificationType,
      notificationSubtype,
      purchaseDate: appleMillisToTimestamp(decodedTransaction.purchaseDate),
      expiresDate: appleMillisToTimestamp(decodedTransaction.expiresDate),
      revocationDate: appleMillisToTimestamp(decodedTransaction.revocationDate),
      signedTransactionInfo,
      signedRenewalInfo: signedRenewalInfo || null,
      createdAt: transactionSnap.exists
        ? transactionSnap.data().createdAt || admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    transaction.set(entitlementRef, nextEntitlement, { merge: true });
  });
}

function deriveEntitlementUpdate(current, decodedTransaction, environment) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const productID = normalizedProductID(decodedTransaction);
  const transactionID = normalizedTransactionID(decodedTransaction);
  const originalTransactionID = normalizedOriginalTransactionID(decodedTransaction);
  const update = {
    schemaVersion: 1,
    appAccountToken: current.appAccountToken,
    environment,
    lastVerifiedAt: now,
    updatedAt: now,
  };

  if (productID === FOUNDER_PRODUCT_ID) {
    const isRevoked = !!decodedTransaction.revocationDate;
    update.isFounderSupporter = !isRevoked;
    update.founderOriginalTransactionID = originalTransactionID;
    update.founderLatestTransactionID = transactionID;
    update.founderPurchasedAt = appleMillisToTimestamp(decodedTransaction.purchaseDate);
    update.founderRevokedAt = appleMillisToTimestamp(decodedTransaction.revocationDate);
    update.membershipTier = current.membershipTier || "free";
    update.premiumStatus = current.premiumStatus || "none";
    update.premiumInGracePeriod = current.premiumInGracePeriod || false;
    update.premiumInBillingRetry = current.premiumInBillingRetry || false;
    return update;
  }

  const expiresDate = appleMillisToDate(decodedTransaction.expiresDate);
  const revoked = !!decodedTransaction.revocationDate;
  const activeByDate = expiresDate ? expiresDate.getTime() > Date.now() : false;
  const premiumStatus = revoked ? "revoked" : (activeByDate ? "active" : "expired");

  update.membershipTier = premiumStatus === "active" ? "premium" : "free";
  update.premiumProductID = productID;
  update.premiumOriginalTransactionID = originalTransactionID;
  update.premiumLatestTransactionID = transactionID;
  update.premiumExpirationDate = appleMillisToTimestamp(decodedTransaction.expiresDate);
  update.premiumStatus = premiumStatus;
  update.premiumWillRenew = current.premiumWillRenew || null;
  update.premiumInGracePeriod = false;
  update.premiumInBillingRetry = false;
  update.isFounderSupporter = current.isFounderSupporter || false;
  return update;
}

async function reconcileOriginalTransactionForUID(uid, originalTransactionID) {
  const client = appStoreClient();
  const request = {
    sort: Order.ASCENDING,
    productTypes: [ProductType.AUTO_RENEWABLE, ProductType.NON_CONSUMABLE],
  };

  let revisionToken = null;
  let processed = 0;
  do {
    const response = await client.getTransactionHistory(
      originalTransactionID,
      revisionToken,
      request,
      GetTransactionHistoryVersion.V2
    );

    const signedTransactions = response.signedTransactions || [];
    for (const signedTransactionInfo of signedTransactions) {
      const verified = await verifySignedTransaction(signedTransactionInfo);
      await processVerifiedTransactionForUID({
        uid,
        decodedTransaction: verified.decodedTransaction,
        signedTransactionInfo,
        signedRenewalInfo: null,
        notificationType: "RECONCILE",
        environment: verified.environmentName,
        allowCreateBinding: true,
      });
      processed += 1;
    }

    revisionToken = response.revision || null;
    if (!response.hasMore) {
      break;
    }
  } while (revisionToken);

  return processed;
}

async function claimAppStoreNotificationEvent(eventRef, notification) {
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(eventRef);
    if (snap.exists) {
      const status = (snap.data() || {}).status;
      if (status === "processed" || status === "skipped") {
        return false;
      }
    }

    transaction.set(eventRef, {
      notificationUUID: notification.notificationUUID || eventRef.id,
      notificationType: notification.notificationType || "UNKNOWN",
      subtype: notification.subtype || null,
      status: "processing",
      createdAt: snap.exists
        ? snap.data().createdAt || admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });
}

async function uidForAppAccountToken(appAccountToken) {
  if (!appAccountToken) {
    return null;
  }
  const snap = await db.collection("appAccountTokens").doc(appAccountToken).get();
  return snap.exists ? snap.data().uid : null;
}

function normalizedProductID(decodedTransaction) {
  return decodedTransaction.productId || decodedTransaction.productID || "";
}

function normalizedTransactionID(decodedTransaction) {
  const raw = decodedTransaction.transactionId || decodedTransaction.transactionID || decodedTransaction.id;
  return raw == null ? "" : String(raw);
}

function normalizedOriginalTransactionID(decodedTransaction) {
  const raw = decodedTransaction.originalTransactionId || decodedTransaction.originalTransactionID || decodedTransaction.originalID;
  return raw == null ? "" : String(raw);
}

function appleMillisToDate(value) {
  if (value == null) {
    return null;
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    return null;
  }
  return new Date(number);
}

function appleMillisToTimestamp(value) {
  const date = appleMillisToDate(value);
  return date ? admin.firestore.Timestamp.fromDate(date) : null;
}

function normalizedLanguage(languageRaw) {
  const supported = new Set(["English", "Deutsch", "Italiano", "Español", "Français"]);
  return supported.has(languageRaw) ? languageRaw : "English";
}

function localizedPushCopy(languageRaw) {
  switch (normalizedLanguage(languageRaw)) {
    case "Deutsch":
      return {
        newIssueTitle: "Neue PenPal-Ausgabe",
        newIssueBody: (name, month, groupName) => `${name} hat die ${month}-Ausgabe in ${groupName} veröffentlicht.`,
        goldenHeartTitle: "Goldenes Herz freigeschaltet",
        goldenHeartBody: (groupName) => `Alle in ${groupName} haben diesen Monat veröffentlicht.`,
        marginNoteTitle: "Neue Randnotiz",
        marginNoteBody: (name) => `${name} hat eine Notiz in deinem Magazin hinterlassen.`,
      };
    case "Italiano":
      return {
        newIssueTitle: "Nuovo giornale PenPal",
        newIssueBody: (name, month, groupName) => `${name} ha pubblicato il suo giornale di ${month} in ${groupName}.`,
        goldenHeartTitle: "Cuore d’oro sbloccato",
        goldenHeartBody: (groupName) => `Tutti in ${groupName} hanno pubblicato questo mese.`,
        marginNoteTitle: "Nuova nota a margine",
        marginNoteBody: (name) => `${name} ha lasciato una nota nel tuo magazine.`,
      };
    case "Español":
      return {
        newIssueTitle: "Nueva revista PenPal",
        newIssueBody: (name, month, groupName) => `${name} publicó su revista de ${month} en ${groupName}.`,
        goldenHeartTitle: "Corazón dorado desbloqueado",
        goldenHeartBody: (groupName) => `Todos en ${groupName} publicaron este mes.`,
        marginNoteTitle: "Nueva nota al margen",
        marginNoteBody: (name) => `${name} ha dejado una nota en tu revista.`,
      };
    case "Français":
      return {
        newIssueTitle: "Nouveau magazine PenPal",
        newIssueBody: (name, month, groupName) => `${name} a publié son magazine de ${month} dans ${groupName}.`,
        goldenHeartTitle: "Coeur doré débloqué",
        goldenHeartBody: (groupName) => `Tout le monde dans ${groupName} a publié ce mois-ci.`,
        marginNoteTitle: "Nouvelle note en marge",
        marginNoteBody: (name) => `${name} a laissé une note dans ton magazine.`,
      };
    default:
      return {
        newIssueTitle: "New PenPal issue",
        newIssueBody: (name, month, groupName) => `${name} published their ${month} issue in ${groupName}.`,
        goldenHeartTitle: "Golden heart unlocked",
        goldenHeartBody: (groupName) => `Everyone in ${groupName} published this month.`,
        marginNoteTitle: "New margin note",
        marginNoteBody: (name) => `${name} left a note in your magazine.`,
      };
  }
}
