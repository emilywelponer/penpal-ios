const fs = require("fs");
const path = require("path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  addDoc,
  serverTimestamp,
} = require("firebase/firestore");

const projectId = "penpal-commerce-rules-test";

describe("commerce Firestore rules", () => {
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users/owner/privateEntitlements/current"), {
        schemaVersion: 1,
        membershipTier: "premium",
        isFounderSupporter: true,
        appAccountToken: "11111111-1111-4111-8111-111111111111",
      });
      await setDoc(doc(db, "users/other/privateEntitlements/current"), {
        schemaVersion: 1,
        membershipTier: "free",
        isFounderSupporter: false,
        appAccountToken: "22222222-2222-4222-8222-222222222222",
      });
      await setDoc(doc(db, "users/publicFounderOnly"), {
        founderSupporter: true,
        displayName: "Public Founder Flag",
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  function authed(uid) {
    return testEnv.authenticatedContext(uid).firestore();
  }

  function anon() {
    return testEnv.unauthenticatedContext().firestore();
  }

  function entitlementRef(db, uid) {
    return doc(db, `users/${uid}/privateEntitlements/current`);
  }

  it("allows only the owner to read their private entitlement", async () => {
    await assertSucceeds(getDoc(entitlementRef(authed("owner"), "owner")));
    await assertFails(getDoc(entitlementRef(anon(), "owner")));
    await assertFails(getDoc(entitlementRef(authed("other"), "owner")));
  });

  it("prevents clients from creating, updating, or deleting private entitlements", async () => {
    await assertFails(setDoc(entitlementRef(authed("owner"), "owner"), {
      isFounderSupporter: false,
    }, { merge: true }));
    await assertFails(setDoc(entitlementRef(authed("newUser"), "newUser"), {
      isFounderSupporter: true,
    }));
    await assertFails(updateDoc(entitlementRef(authed("owner"), "owner"), {
      membershipTier: "free",
    }));
    await assertFails(deleteDoc(entitlementRef(authed("owner"), "owner")));
  });

  it("blocks client access to App Store commerce indexes", async () => {
    for (const collectionName of [
      "appAccountTokens",
      "appStoreOriginalTransactions",
      "appStoreTransactions",
      "appStoreNotificationEvents",
    ]) {
      const ref = doc(authed("owner"), `${collectionName}/test-id`);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { uid: "owner" }));
    }
  });

  it("does not allow a public founderSupporter field to unlock PenPal Lab", async () => {
    const db = authed("publicFounderOnly");
    const suggestionRef = doc(db, "penpalLabSuggestions/public-flag-test");
    await assertFails(getDoc(suggestionRef));
    await assertFails(setDoc(suggestionRef, validSuggestion("publicFounderOnly")));
  });

  it("allows backend-authorized Founder users to read and create PenPal Lab suggestions", async () => {
    const db = authed("owner");
    const suggestionRef = doc(db, "penpalLabSuggestions/founder-test");
    await assertSucceeds(setDoc(suggestionRef, validSuggestion("owner")));
    await assertSucceeds(getDoc(suggestionRef));
  });

  it("blocks non-Founder PenPal Lab actions", async () => {
    const db = authed("other");
    await assertFails(addDoc(collection(db, "penpalLabSuggestions"), validSuggestion("other")));
    await assertFails(getDoc(doc(db, "penpalLabSuggestions/founder-test")));
  });
});

function validSuggestion(uid) {
  return {
    authorID: uid,
    authorDisplayName: "Test Founder",
    title: "A calmer roadmap",
    description: "Please keep PenPal thoughtful and slow.",
    category: "feature",
    status: "under_review",
    isVisible: true,
    voteCount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}
