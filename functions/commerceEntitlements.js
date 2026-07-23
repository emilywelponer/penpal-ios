const FOUNDER_PRODUCT_ID = "com.emily.penpal.founder";
const PREMIUM_MONTHLY_PRODUCT_ID = "com.emily.penpal.premium.monthly";
const PREMIUM_ANNUAL_PRODUCT_ID = "com.emily.penpal.premium.annual";
const PREMIUM_PRODUCT_IDS = new Set([
  PREMIUM_MONTHLY_PRODUCT_ID,
  PREMIUM_ANNUAL_PRODUCT_ID,
]);

function deriveEntitlementUpdate({
  current,
  decodedTransaction,
  decodedRenewalInfo = null,
  notificationType = "UNKNOWN",
  environment,
  serverTimestamp,
  timestampFromMillis,
  nowDate = new Date(),
}) {
  const now = serverTimestamp();
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
    update.founderPurchasedAt = timestampFromMillis(decodedTransaction.purchaseDate);
    update.founderRevokedAt = timestampFromMillis(decodedTransaction.revocationDate);
    update.membershipTier = current.membershipTier || "free";
    update.premiumStatus = current.premiumStatus || "none";
    update.premiumInGracePeriod = current.premiumInGracePeriod || false;
    update.premiumInBillingRetry = current.premiumInBillingRetry || false;
    return update;
  }

  const expiresDate = appleMillisToDate(decodedTransaction.expiresDate);
  const revoked = !!decodedTransaction.revocationDate;
  const activeByDate = expiresDate ? expiresDate.getTime() > nowDate.getTime() : false;
  const premiumStatus = premiumStatusFromTransaction(
    decodedTransaction,
    decodedRenewalInfo,
    notificationType,
    nowDate
  );
  const currentExpiration = current.premiumExpirationDate && current.premiumExpirationDate.toDate
    ? current.premiumExpirationDate.toDate()
    : null;
  const incomingIsOlderPremium = currentExpiration
    && expiresDate
    && expiresDate.getTime() < currentExpiration.getTime()
    && current.premiumOriginalTransactionID !== originalTransactionID;

  if (incomingIsOlderPremium && !revoked) {
    return {
      schemaVersion: 1,
      appAccountToken: current.appAccountToken,
      environment,
      lastVerifiedAt: now,
      updatedAt: now,
      membershipTier: current.membershipTier || "free",
      isFounderSupporter: current.isFounderSupporter || false,
      premiumStatus: current.premiumStatus || "none",
      premiumInGracePeriod: current.premiumInGracePeriod || false,
      premiumInBillingRetry: current.premiumInBillingRetry || false,
    };
  }

  update.membershipTier = ["active", "gracePeriod"].includes(premiumStatus) || (!revoked && activeByDate) ? "premium" : "free";
  update.premiumProductID = productID;
  update.premiumOriginalTransactionID = originalTransactionID;
  update.premiumLatestTransactionID = transactionID;
  update.premiumExpirationDate = timestampFromMillis(decodedTransaction.expiresDate);
  update.premiumStatus = premiumStatus;
  update.premiumWillRenew = renewalWillRenew(decodedRenewalInfo);
  update.premiumInGracePeriod = premiumStatus === "gracePeriod";
  update.premiumInBillingRetry = premiumStatus === "billingRetry";
  update.isFounderSupporter = current.isFounderSupporter || false;
  return update;
}

function premiumStatusFromTransaction(decodedTransaction, decodedRenewalInfo, notificationType, nowDate = new Date()) {
  if (decodedTransaction.revocationDate) {
    return "revoked";
  }

  if (notificationType === "GRACE_PERIOD_EXPIRED") {
    return "expired";
  }

  if (notificationType === "DID_FAIL_TO_RENEW") {
    return "billingRetry";
  }

  const gracePeriodExpiresDate = appleMillisToDate(decodedRenewalInfo && decodedRenewalInfo.gracePeriodExpiresDate);
  if (gracePeriodExpiresDate && gracePeriodExpiresDate.getTime() > nowDate.getTime()) {
    return "gracePeriod";
  }

  const expiresDate = appleMillisToDate(decodedTransaction.expiresDate);
  if (expiresDate && expiresDate.getTime() > nowDate.getTime()) {
    return "active";
  }

  return "expired";
}

function renewalWillRenew(decodedRenewalInfo) {
  if (!decodedRenewalInfo || decodedRenewalInfo.autoRenewStatus == null) {
    return null;
  }

  return decodedRenewalInfo.autoRenewStatus === 1
    || decodedRenewalInfo.autoRenewStatus === "1"
    || decodedRenewalInfo.autoRenewStatus === "ON";
}

function appleMillisToDate(value) {
  if (value == null) {
    return null;
  }
  const millis = Number(value);
  if (!Number.isFinite(millis) || millis <= 0) {
    return null;
  }
  return new Date(millis);
}

function normalizedProductID(decodedTransaction) {
  return decodedTransaction.productId || decodedTransaction.productID || "";
}

function normalizedTransactionID(decodedTransaction) {
  const raw = decodedTransaction.transactionId || decodedTransaction.transactionID;
  return raw == null ? "" : String(raw);
}

function normalizedOriginalTransactionID(decodedTransaction) {
  const raw = decodedTransaction.originalTransactionId || decodedTransaction.originalTransactionID;
  return raw == null ? "" : String(raw);
}

module.exports = {
  FOUNDER_PRODUCT_ID,
  PREMIUM_MONTHLY_PRODUCT_ID,
  PREMIUM_ANNUAL_PRODUCT_ID,
  PREMIUM_PRODUCT_IDS,
  deriveEntitlementUpdate,
  premiumStatusFromTransaction,
  renewalWillRenew,
};
