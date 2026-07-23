const assert = require("assert");
const {
  FOUNDER_PRODUCT_ID,
  PREMIUM_MONTHLY_PRODUCT_ID,
  PREMIUM_ANNUAL_PRODUCT_ID,
  deriveEntitlementUpdate,
} = require("../../functions/commerceEntitlements");

const fixedNow = new Date("2026-07-23T12:00:00.000Z");

describe("commerce entitlement derivation", () => {
  it("grants Founder without changing an existing Premium subscription", () => {
    const update = deriveEntitlementUpdate({
      current: currentPremium(),
      decodedTransaction: founderTransaction(),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.isFounderSupporter, true);
    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumStatus, "active");
  });

  it("grants monthly Premium without changing existing Founder access", () => {
    const update = deriveEntitlementUpdate({
      current: currentFounder(),
      decodedTransaction: premiumTransaction(PREMIUM_MONTHLY_PRODUCT_ID, "monthly-original", monthsFromNow(1)),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumProductID, PREMIUM_MONTHLY_PRODUCT_ID);
    assert.equal(update.isFounderSupporter, true);
  });

  it("maps annual Premium to the same Premium entitlement", () => {
    const update = deriveEntitlementUpdate({
      current: { appAccountToken: "token", isFounderSupporter: false },
      decodedTransaction: premiumTransaction(PREMIUM_ANNUAL_PRODUCT_ID, "annual-original", monthsFromNow(12)),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumProductID, PREMIUM_ANNUAL_PRODUCT_ID);
    assert.equal(update.premiumStatus, "active");
  });

  it("cancellation with future expiration keeps Premium active but willRenew false", () => {
    const update = deriveEntitlementUpdate({
      current: { appAccountToken: "token" },
      decodedTransaction: premiumTransaction(PREMIUM_MONTHLY_PRODUCT_ID, "monthly-original", monthsFromNow(1)),
      decodedRenewalInfo: { autoRenewStatus: 0 },
      notificationType: "DID_CHANGE_RENEWAL_STATUS",
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumStatus, "active");
    assert.equal(update.premiumWillRenew, false);
  });

  it("expired Premium becomes Free without removing Founder", () => {
    const update = deriveEntitlementUpdate({
      current: currentFounder(),
      decodedTransaction: premiumTransaction(PREMIUM_MONTHLY_PRODUCT_ID, "monthly-original", monthsAgo(1)),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "free");
    assert.equal(update.premiumStatus, "expired");
    assert.equal(update.isFounderSupporter, true);
  });

  it("Founder revocation does not remove Premium", () => {
    const update = deriveEntitlementUpdate({
      current: currentPremium(),
      decodedTransaction: founderTransaction({ revocationDate: fixedNow.getTime() }),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.isFounderSupporter, false);
    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumStatus, "active");
  });

  it("Premium revocation does not remove Founder", () => {
    const update = deriveEntitlementUpdate({
      current: currentFounder(),
      decodedTransaction: premiumTransaction(PREMIUM_ANNUAL_PRODUCT_ID, "annual-original", monthsFromNow(10), {
        revocationDate: fixedNow.getTime(),
      }),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "free");
    assert.equal(update.premiumStatus, "revoked");
    assert.equal(update.isFounderSupporter, true);
  });

  it("older Premium history does not erase a newer active Premium transaction", () => {
    const current = currentPremium({
      premiumOriginalTransactionID: "newer-original",
      premiumExpirationDate: timestampFromMillis(monthsFromNow(12)),
    });

    const update = deriveEntitlementUpdate({
      current,
      decodedTransaction: premiumTransaction(PREMIUM_MONTHLY_PRODUCT_ID, "older-original", monthsFromNow(1)),
      environment: "Production",
      serverTimestamp,
      timestampFromMillis,
      nowDate: fixedNow,
    });

    assert.equal(update.membershipTier, "premium");
    assert.equal(update.premiumStatus, "active");
    assert.equal(update.premiumProductID, undefined);
  });
});

function currentPremium(overrides = {}) {
  return {
    appAccountToken: "token",
    membershipTier: "premium",
    premiumStatus: "active",
    premiumInGracePeriod: false,
    premiumInBillingRetry: false,
    isFounderSupporter: false,
    premiumOriginalTransactionID: "premium-original",
    premiumExpirationDate: timestampFromMillis(monthsFromNow(1)),
    ...overrides,
  };
}

function currentFounder() {
  return {
    appAccountToken: "token",
    membershipTier: "free",
    premiumStatus: "none",
    premiumInGracePeriod: false,
    premiumInBillingRetry: false,
    isFounderSupporter: true,
  };
}

function founderTransaction(overrides = {}) {
  return {
    productId: FOUNDER_PRODUCT_ID,
    transactionId: "founder-latest",
    originalTransactionId: "founder-original",
    purchaseDate: fixedNow.getTime(),
    ...overrides,
  };
}

function premiumTransaction(productId, originalTransactionId, expiresDate, overrides = {}) {
  return {
    productId,
    transactionId: `${originalTransactionId}-latest`,
    originalTransactionId,
    purchaseDate: fixedNow.getTime(),
    expiresDate,
    ...overrides,
  };
}

function monthsFromNow(count) {
  return fixedNow.getTime() + count * 30 * 24 * 60 * 60 * 1000;
}

function monthsAgo(count) {
  return fixedNow.getTime() - count * 30 * 24 * 60 * 60 * 1000;
}

function serverTimestamp() {
  return "SERVER_TIMESTAMP";
}

function timestampFromMillis(millis) {
  if (millis == null) {
    return null;
  }
  return {
    millis,
    toDate() {
      return new Date(millis);
    },
  };
}
