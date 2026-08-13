const fs = require("fs");
const path = require("path");
const { assertFails, assertSucceeds, initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp } = require("firebase/firestore");

describe("content Firestore rules", () => {
  let env;
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "penpal-content-rules-test",
      firestore: { rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8") },
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "groups/g1"), { id: "g1", ownerID: "owner", memberIDs: ["owner", "member"], createdAt: Timestamp.now(), name: "Friends" });
      await setDoc(doc(db, "publishedIssues/i1"), {
        id: "i1", ownerID: "owner", groupIDs: ["g1"], authorizedReaderIDs: ["owner", "member"],
        createdAt: Timestamp.now(), title: "Private", retentionState: "accessible",
      });
      await setDoc(doc(db, "users/owner/privateEntitlements/current"), { membershipTier: "free", premiumStatus: "none", isFounderSupporter: false });
      await setDoc(doc(db, "users/member/privateEntitlements/current"), { membershipTier: "free", premiumStatus: "none", isFounderSupporter: false });
    });
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();

  it("prevents an unrelated user from modifying another group", async () => {
    await assertFails(updateDoc(doc(db("stranger"), "groups/g1"), { name: "Stolen" }));
  });
  it("allows only members to read a group", async () => {
    await assertSucceeds(getDoc(doc(db("member"), "groups/g1")));
    await assertFails(getDoc(doc(db("stranger"), "groups/g1")));
  });
  it("allows an invite join but no unrelated field mutation", async () => {
    await assertSucceeds(updateDoc(doc(db("invitee"), "groups/g1"), { memberIDs: ["owner", "member", "invitee"] }));
    await assertFails(updateDoc(doc(db("invitee"), "groups/g1"), { memberIDs: ["owner", "member", "invitee"], name: "Changed" }));
  });
  it("restricts issue reads to authorized readers", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), "publishedIssues/i1")));
    await assertSucceeds(getDoc(doc(db("member"), "publishedIssues/i1")));
    await assertFails(getDoc(doc(db("stranger"), "publishedIssues/i1")));
  });
  it("preserves issue ownership", async () => {
    await assertFails(updateDoc(doc(db("owner"), "publishedIssues/i1"), { ownerID: "stranger" }));
    await assertSucceeds(deleteDoc(doc(db("owner"), "publishedIssues/i1")));
  });
});
