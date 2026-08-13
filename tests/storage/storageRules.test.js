const fs = require("fs");
const path = require("path");
const { assertFails, assertSucceeds, initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { doc, setDoc, Timestamp } = require("firebase/firestore");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");

describe("published media Storage rules", () => {
  let env;
  before(async () => {
    // Cross-service Storage Rules lookups run against the project configured by
    // `firebase emulators:exec`. Keep the test clients in that same project so
    // Firestore ownership/session fixtures are visible to Storage Rules.
    const projectId = process.env.GCLOUD_PROJECT || "demo-no-project";
    env = await initializeTestEnvironment({
      projectId,
      firestore: { rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8") },
      storage: { rules: fs.readFileSync(path.join(__dirname, "../../storage.rules"), "utf8") },
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "publishedIssues/i1"), {
        id: "i1", ownerID: "owner", authorizedReaderIDs: ["owner", "member"], groupIDs: ["g1"],
        createdAt: Timestamp.now(), retentionState: "accessible",
      });
      await setDoc(doc(db, "users/owner/privateEntitlements/current"), { membershipTier: "free", premiumStatus: "none" });
      await setDoc(doc(db, "users/member/privateEntitlements/current"), { membershipTier: "free", premiumStatus: "none" });
      await setDoc(doc(db, "issueUploadSessions/newIssue"), { issueID: "newIssue", ownerID: "owner" });
    });
  });
  const storage = (uid) => env.authenticatedContext(uid).storage();
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const json = new TextEncoder().encode("{}");

  it("lets the owner upload and an authorized member read published media", async () => {
    const ownerRef = ref(storage("owner"), "publishedIssues/i1/images/a.jpg");
    await assertSucceeds(uploadBytes(ownerRef, jpeg, { contentType: "image/jpeg" }));
    await assertSucceeds(getBytes(ref(storage("member"), "publishedIssues/i1/images/a.jpg")));
    await assertFails(getBytes(ref(storage("stranger"), "publishedIssues/i1/images/a.jpg")));
  });
  it("prevents unrelated users from overwriting published media", async () => {
    await assertFails(uploadBytes(ref(storage("stranger"), "publishedIssues/i1/images/a.jpg"), jpeg, { contentType: "image/jpeg" }));
  });
  it("allows published JSON through an owner upload session and rejects JPEG MIME", async () => {
    const jsonRef = ref(storage("owner"), "publishedIssues/newIssue/draftData/pageDraftData.json");
    await assertSucceeds(uploadBytes(jsonRef, json, { contentType: "application/json" }));
    await assertFails(uploadBytes(ref(storage("owner"), "publishedIssues/newIssue/draftData/bad.json"), jpeg, { contentType: "image/jpeg" }));
  });
  it("allows the issue owner to delete media", async () => {
    const objectRef = ref(storage("owner"), "publishedIssues/i1/images/delete.jpg");
    await uploadBytes(objectRef, jpeg, { contentType: "image/jpeg" });
    await assertSucceeds(deleteObject(objectRef));
  });
});
