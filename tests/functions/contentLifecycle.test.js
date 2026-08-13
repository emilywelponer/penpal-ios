const assert = require("assert");
const {
  FREE_ACCESSIBLE_MONTHS,
  FREE_DELETION_GRACE_MONTHS,
  hasPremiumRetention,
  retentionDecision,
  deleteDraftStorage,
  deleteIssueStorage,
  deleteAccountOwnedStorage,
} = require("../../functions/contentLifecycle");

describe("archive retention", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  const free = { membershipTier: "free", premiumStatus: "none", isFounderSupporter: false };
  const founder = { membershipTier: "free", premiumStatus: "none", isFounderSupporter: true };
  const premium = { membershipTier: "premium", premiumStatus: "active" };

  it("keeps the configured two-month Free window", () => {
    assert.equal(FREE_ACCESSIBLE_MONTHS, 2);
    assert.equal(retentionDecision({ issueDate: new Date("2026-07-01"), entitlement: free, now }).state, "accessible");
  });

  it("locks Free issues after two months without immediately deleting", () => {
    const result = retentionDecision({ issueDate: new Date("2026-05-20"), entitlement: free, now });
    assert.equal(result.state, "locked");
    assert.equal(result.deleteEligible, false);
  });

  it("selects Free issues only after the deletion grace period", () => {
    assert.equal(FREE_DELETION_GRACE_MONTHS, 1);
    const result = retentionDecision({ issueDate: new Date("2026-04-01"), entitlement: free, now });
    assert.equal(result.deleteEligible, true);
  });

  it("keeps Premium archives accessible", () => {
    assert.equal(hasPremiumRetention(premium, now), true);
    assert.equal(retentionDecision({ issueDate: new Date("2020-01-01"), entitlement: premium, now }).state, "accessible");
  });

  it("does not treat Founder alone as Premium", () => {
    assert.equal(hasPremiumRetention(founder, now), false);
    assert.equal(retentionDecision({ issueDate: new Date("2020-01-01"), entitlement: founder, now }).deleteEligible, true);
  });

  it("applies Free retention after Premium expiration", () => {
    const expired = { membershipTier: "free", premiumStatus: "expired", isFounderSupporter: true };
    assert.equal(retentionDecision({ issueDate: new Date("2020-01-01"), entitlement: expired, now }).state, "locked");
  });

  it("deletes only the requested draft prefix", async () => {
    const deleted = [];
    const bucket = fakeBucket([
      "issueDrafts/owner/d1/images/a.jpg",
      "issueDrafts/owner/d1/draftData/pageDraftData.json",
      "issueDrafts/owner/d2/images/keep.jpg",
    ], deleted);
    await deleteDraftStorage(bucket, "owner", "d1");
    assert.deepEqual(deleted.sort(), [
      "issueDrafts/owner/d1/draftData/pageDraftData.json",
      "issueDrafts/owner/d1/images/a.jpg",
    ]);
  });

  it("deletes all and only the requested published issue prefix", async () => {
    const deleted = [];
    const bucket = fakeBucket([
      "publishedIssues/i1/images/a.jpg",
      "publishedIssues/i1/draftData/pageDraftData.json",
      "publishedIssues/i2/images/keep.jpg",
    ], deleted);
    await deleteIssueStorage(bucket, "i1");
    assert.equal(deleted.length, 2);
    assert(deleted.every((path) => path.startsWith("publishedIssues/i1/")));
  });

  it("account cleanup removes only user-owned draft, issue, and user prefixes", async () => {
    const deleted = [];
    const bucket = fakeBucket([
      "issueDrafts/owner/d1/images/a.jpg", "issueDrafts/other/d2/images/keep.jpg",
      "publishedIssues/i1/images/a.jpg", "publishedIssues/i2/images/keep.jpg",
      "users/owner/profile.jpg", "users/other/profile.jpg",
    ], deleted);
    await deleteAccountOwnedStorage(bucket, "owner", ["d1"], ["i1"]);
    assert.deepEqual(deleted.sort(), [
      "issueDrafts/owner/d1/images/a.jpg",
      "publishedIssues/i1/images/a.jpg",
      "users/owner/profile.jpg",
    ]);
  });
});

function fakeBucket(paths, deleted) {
  return {
    async getFiles({ prefix }) {
      return [paths.filter((name) => name.startsWith(prefix)).map((name) => ({
        name,
        async delete() { deleted.push(name); },
      }))];
    },
  };
}
