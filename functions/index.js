const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

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
    return;
  }

  let successCount = 0;
  let failureCount = 0;

  const badgeCounts = new Map();
  await Promise.all(userIDs.map(async (uid) => {
    badgeCounts.set(uid, await unreadGroupIssueCount(uid));
  }));

  const messages = tokenRecords.map(({ token, userID, languageRaw }) => {
    const payload = payloadForLanguage(languageRaw);
    return {
      token,
      notification: payload.notification,
      data: payload.data,
      apns: {
        payload: {
          aps: {
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
      logger.warn("PUSH_SEND_TOKEN_ERROR", {
        ...logData,
        userID: tokenRecords[index].userID,
        error: result.error && result.error.message,
      });
    }
  });

  logger.info(logLabel, {
    ...logData,
    tokenCount: tokenRecords.length,
    successCount,
    failureCount,
  });
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
      };
    case "Italiano":
      return {
        newIssueTitle: "Nuovo giornale PenPal",
        newIssueBody: (name, month, groupName) => `${name} ha pubblicato il suo giornale di ${month} in ${groupName}.`,
        goldenHeartTitle: "Cuore d’oro sbloccato",
        goldenHeartBody: (groupName) => `Tutti in ${groupName} hanno pubblicato questo mese.`,
      };
    case "Español":
      return {
        newIssueTitle: "Nueva revista PenPal",
        newIssueBody: (name, month, groupName) => `${name} publicó su revista de ${month} en ${groupName}.`,
        goldenHeartTitle: "Corazón dorado desbloqueado",
        goldenHeartBody: (groupName) => `Todos en ${groupName} publicaron este mes.`,
      };
    case "Français":
      return {
        newIssueTitle: "Nouveau magazine PenPal",
        newIssueBody: (name, month, groupName) => `${name} a publié son magazine de ${month} dans ${groupName}.`,
        goldenHeartTitle: "Coeur doré débloqué",
        goldenHeartBody: (groupName) => `Tout le monde dans ${groupName} a publié ce mois-ci.`,
      };
    default:
      return {
        newIssueTitle: "New PenPal issue",
        newIssueBody: (name, month, groupName) => `${name} published their ${month} issue in ${groupName}.`,
        goldenHeartTitle: "Golden heart unlocked",
        goldenHeartBody: (groupName) => `Everyone in ${groupName} published this month.`,
      };
  }
}
