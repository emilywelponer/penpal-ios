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
