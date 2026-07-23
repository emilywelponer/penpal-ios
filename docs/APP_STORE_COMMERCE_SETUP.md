# PenPal App Store Commerce Setup

This document covers the manual setup and validation required before PenPal commerce can be considered production-ready. The code expects these exact product identifiers:

- Founder Supporter: `com.emily.penpal.founder`
- Premium Monthly: `com.emily.penpal.premium.monthly`
- Premium Annual: `com.emily.penpal.premium.annual`
- Bundle ID: `com.emily.penpal`
- Subscription group: `PenPal Premium`

## Manual App Store Connect Setup

1. Accept the Paid Apps Agreement in App Store Connect.
2. Complete banking and tax information.
3. Confirm Small Business Program status if applicable.
4. Create the non-consumable product `com.emily.penpal.founder`.
5. Create one auto-renewable subscription group named `PenPal Premium`.
6. Create monthly subscription `com.emily.penpal.premium.monthly` in that group.
7. Create annual subscription `com.emily.penpal.premium.annual` in that group.
8. Keep monthly and annual at the same subscription service level.
9. Do not create Plus, Pro, lifetime Premium, consumables, or separate subscription groups.
10. Add App Store localizations for all products.
11. Configure prices and availability.
12. Add subscription review screenshots and review notes.
13. Add Privacy Policy URL.
14. Add Terms of Use URL.
15. Create Sandbox testers.
16. Create an App Store Connect API key with App Store Server API access.
17. Configure Firebase secrets listed below.
18. Deploy Firebase Functions and Firestore rules.
19. Configure App Store Server Notifications V2 Sandbox URL.
20. Configure App Store Server Notifications V2 Production URL.
21. Test through Apple Sandbox.
22. Test through TestFlight.
23. Submit the first in-app purchase with an app version.

Apple pays proceeds through the banking/tax setup in App Store Connect. Financial reports are available in App Store Connect under Payments and Financial Reports.

## Firebase Secrets

Set these with Firebase CLI. Replace values with real App Store Connect values; do not commit private keys.

```sh
firebase functions:secrets:set APPLE_ISSUER_ID
firebase functions:secrets:set APPLE_KEY_ID
firebase functions:secrets:set APPLE_PRIVATE_KEY
firebase functions:secrets:set APPLE_APP_APPLE_ID
firebase functions:secrets:set APPLE_ROOT_CERTIFICATES_BASE64_JSON
firebase functions:secrets:set APPLE_ENVIRONMENT
firebase functions:secrets:set APPLE_ALLOWED_ENVIRONMENTS
```

Expected values:

- `APPLE_ISSUER_ID`: App Store Connect issuer UUID.
- `APPLE_KEY_ID`: App Store Connect API key ID.
- `APPLE_PRIVATE_KEY`: private key contents for the App Store Connect API key.
- `APPLE_APP_APPLE_ID`: numeric Apple app ID. Required for Production verification.
- `APPLE_ROOT_CERTIFICATES_BASE64_JSON`: JSON array of base64-encoded Apple root certificate contents required by `@apple/app-store-server-library`.
- `APPLE_ENVIRONMENT`: exactly `Sandbox` or `Production`.
- `APPLE_ALLOWED_ENVIRONMENTS`: comma-separated allowed verifier environments. Use `Sandbox` for a development Firebase project and `Production` for production. Avoid allowing both in the production Firebase project unless there is an intentional, documented reason.

The backend fails closed when required commerce configuration is missing or malformed.

## Deployment

```sh
firebase deploy --only functions
firebase deploy --only firestore:rules
```

After deployment, configure App Store Server Notifications V2:

- Sandbox URL: `https://<region>-<firebase-project>.cloudfunctions.net/appStoreServerNotificationsV2`
- Production URL: `https://<region>-<firebase-project>.cloudfunctions.net/appStoreServerNotificationsV2`

Use separate Firebase projects for Sandbox/TestFlight and Production where possible, so Sandbox transactions cannot affect production entitlement documents.

## Sandbox End-to-End Test Plan

Use two real PenPal accounts and at least one physical iPhone. Push StoreKit local configuration is not enough for final validation.

### Founder Supporter

1. Purchase Founder on Account A.
   - Apple state: non-consumable owned by the Sandbox Apple ID.
   - Private entitlement: `isFounderSupporter: true`, `membershipTier` unchanged.
   - UI: Founder badge and PenPal Lab access after backend entitlement loads.
   - Bindings: `appStoreOriginalTransactions/{environment}_{originalTransactionID}` belongs to Account A.
2. Restart the app.
   - Expected: entitlement reloads from Firestore, not from UserDefaults.
3. Reinstall the app and log into Account A.
   - Expected: restore/reconciliation keeps Founder access.
4. Restore on another device signed into Account A.
   - Expected: same backend entitlement and no duplicate grant.
5. Log out, log into Account B on the same device, and attempt restore.
   - Expected: transaction already linked to Account A; Account B does not receive Founder.
6. Refund/revoke Founder where Sandbox tooling permits.
   - Expected: Founder becomes false; Premium state is unchanged.

### Premium

1. Purchase monthly Premium.
   - Apple state: active subscription.
   - Entitlement: `membershipTier: premium`, monthly product ID, active status.
   - UI: Premium plan status only after backend entitlement confirms.
2. Purchase annual Premium or switch billing duration.
   - Expected: annual and monthly both map to Premium; latest verified state wins.
3. Cancel renewal while still paid through.
   - Expected: Premium remains active until expiration, `premiumWillRenew: false`.
4. Let Sandbox subscription expire.
   - Expected: `membershipTier: free`, Founder unchanged.
5. Test renewal.
   - Expected: expiration date advances idempotently.
6. Test billing retry/grace period where Sandbox allows.
   - Expected: status reflects billing retry or grace period; access follows Apple entitlement state.
7. Restore after reinstall and on another device.
   - Expected: backend reconciliation updates the same Account A entitlement.
8. Attempt restore while logged into Account B.
   - Expected: purchase cannot be silently transferred.
9. Refund/revoke Premium where Sandbox tooling permits.
   - Expected: Premium removed; Founder unchanged.

### Coexistence

1. Founder first, then Premium.
   - Expected: `isFounderSupporter: true` and `membershipTier: premium`.
2. Premium first, then Founder.
   - Expected: both remain active independently.
3. Premium expiration.
   - Expected: Premium becomes Free; Founder remains true.
4. Founder revocation.
   - Expected: Founder false; Premium remains according to subscription state.

### Server Notification Checks

For each Apple notification:

- `appStoreNotificationEvents/{notificationUUID}` is created once.
- Duplicate notifications do not apply duplicate entitlement changes.
- Signed payloads are verified before processing.
- Full signed payloads and private transaction data are not logged.

## Release Readiness Criteria

Commerce is not production-ready until all of these are true:

- iOS executable monetization tests pass.
- backend commerce tests pass.
- Firestore emulator rules tests pass.
- Functions deploy succeeds.
- Firestore rules deploy succeeds.
- real Apple Sandbox Founder purchase succeeds.
- real Apple Sandbox Premium purchase succeeds.
- backend private entitlement is written correctly.
- StoreKit transaction is finished only after backend persistence.
- restore succeeds.
- at least one App Store Server Notification V2 payload is verified and processed.
- Founder and Premium access behave independently.
