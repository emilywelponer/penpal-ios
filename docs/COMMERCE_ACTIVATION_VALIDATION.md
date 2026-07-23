# PenPal Commerce Activation and Sandbox Validation

Commerce remains **NOT READY** until every release gate at the end of this document is checked off with real Apple Sandbox/TestFlight evidence.

Do not start magazine archive, media reuse, monthly issue claims, margin-note migration, or retention work during this phase.

## 1. Deployment Command Sequence

There is currently no `.firebaserc` in this repository. Use explicit `--project "$FIREBASE_PROJECT_ID"` on every Firebase command until a project alias is deliberately added.

Set these shell variables first:

```sh
cd /Applications/Biologie/TravelingFriends

export FIREBASE_PROJECT_ID="<YOUR_FIREBASE_PROJECT_ID>"
export FUNCTIONS_REGION="us-central1"
export APPLE_NOTIFICATION_FUNCTION="appStoreServerNotificationsV2"
```

Authenticate and confirm project:

```sh
firebase login
firebase projects:list
firebase functions:list --project "$FIREBASE_PROJECT_ID"
```

Create/update Firebase secrets. Do not paste placeholder values; obtain these from App Store Connect and Apple documentation first.

```sh
firebase functions:secrets:set APPLE_ISSUER_ID --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_KEY_ID --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_APP_APPLE_ID --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_ENVIRONMENT --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_ALLOWED_ENVIRONMENTS --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_ROOT_CERTIFICATES_BASE64_JSON --project "$FIREBASE_PROJECT_ID"
firebase functions:secrets:set APPLE_PRIVATE_KEY --data-file "<PATH_TO_APP_STORE_CONNECT_PRIVATE_KEY.p8>" --project "$FIREBASE_PROJECT_ID"
```

Recommended environment values:

- Development/Sandbox Firebase project: `APPLE_ENVIRONMENT=Sandbox`, `APPLE_ALLOWED_ENVIRONMENTS=Sandbox`
- Production Firebase project: `APPLE_ENVIRONMENT=Production`, `APPLE_ALLOWED_ENVIRONMENTS=Production`

Deploy:

```sh
firebase deploy --only functions --project "$FIREBASE_PROJECT_ID"
firebase deploy --only firestore:rules --project "$FIREBASE_PROJECT_ID"
```

Inspect deployment:

```sh
firebase functions:list --project "$FIREBASE_PROJECT_ID"
```

If a deploy fails and you need verbose diagnostics, rerun the same deploy command with `--debug`.

Retrieve the App Store Server Notifications V2 endpoint:

```sh
firebase functions:list --project "$FIREBASE_PROJECT_ID"
printf 'https://%s-%s.cloudfunctions.net/%s\n' "$FUNCTIONS_REGION" "$FIREBASE_PROJECT_ID" "$APPLE_NOTIFICATION_FUNCTION"
```

Inspect logs during testing:

```sh
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only getOrCreateAppAccountToken
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only processAppStoreTransaction
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only reconcileAppStoreEntitlements
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only appStoreServerNotificationsV2
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only appStoreServerNotificationsV2 --lines 100
```

Do not deploy until the Firebase project is confirmed.

## 2. Identifier and Value Matching Checklist

| Item | Code location | Manual location | Expected format | Secret | If wrong |
| --- | --- | --- | --- | --- | --- |
| Bundle ID | `functions/index.js` `BUNDLE_ID`, `PenPal/StoreKitProductCatalog.swift`, Xcode project | Apple app record and Xcode Signing | `com.emily.penpal` | No | Apple verification fails with bundle mismatch or StoreKit products do not load. |
| App Apple ID | Firebase secret `APPLE_APP_APPLE_ID` | App Store Connect app information | Numeric ID, for example `<1234567890>` | No, but treat as config | Production signed data verification fails. |
| Founder product ID | `functions/index.js`, `PenPal/StoreKitProductCatalog.swift`, `PenPal/PenPal.storekit` | App Store Connect non-consumable | `com.emily.penpal.founder` | No | Unknown product rejected; purchase will not grant entitlement. |
| Premium monthly product ID | Same as above | App Store Connect subscription | `com.emily.penpal.premium.monthly` | No | Product unavailable or rejected by backend. |
| Premium annual product ID | Same as above | App Store Connect subscription | `com.emily.penpal.premium.annual` | No | Product unavailable or rejected by backend. |
| Subscription group | Documentation/paywall copy | App Store Connect subscription group | `PenPal Premium` | No | StoreKit subscription switching/status may behave incorrectly. |
| Firebase project | CLI `--project`, `GoogleService-Info.plist` | Firebase Console | Project ID string | No | App calls one project while Functions/rules deploy to another. |
| Functions region | `functions/index.js` `FUNCTIONS_REGION`, `setGlobalOptions` | Firebase Functions deployment and notification URL | `us-central1` | No | Callable client and notification URL point to a different region than deployed Functions. |
| Sandbox notification URL | Derived deployed HTTPS function URL | App Store Connect Sandbox Server Notifications | `https://us-central1-<project>.cloudfunctions.net/appStoreServerNotificationsV2` | No | Apple notifications never reach backend. |
| Production notification URL | Same | App Store Connect Production Server Notifications | HTTPS function URL for production Firebase project | No | Production lifecycle events not processed. |
| Apple issuer ID | Secret `APPLE_ISSUER_ID` | App Store Connect API key page | UUID | Yes | App Store Server API reconciliation fails. |
| Apple key ID | Secret `APPLE_KEY_ID` | App Store Connect API key page | 10-character key ID | Yes | App Store Server API reconciliation fails. |
| App Store Connect private key | Secret `APPLE_PRIVATE_KEY` | Downloaded `.p8` file | PEM private key contents | Yes | API client fails; reconciliation fails. |
| Apple root certificates | Secret `APPLE_ROOT_CERTIFICATES_BASE64_JSON` | Apple root certificate files encoded by developer | JSON array of base64 certificate bytes | Yes/config sensitive | JWS verification fails. |
| Allowed environments | Secrets `APPLE_ENVIRONMENT`, `APPLE_ALLOWED_ENVIRONMENTS` | Firebase secrets | `Sandbox` or `Production` | No | Sandbox/Production mismatch causes verification failure or unsafe cross-environment grants. |

## 3. Minimum Founder Sandbox Path

1. App Store Connect: confirm `com.emily.penpal.founder` exists and is available for Sandbox testing.
2. Firebase: configure all secrets with `APPLE_ENVIRONMENT=Sandbox` and `APPLE_ALLOWED_ENVIRONMENTS=Sandbox`.
3. Firebase: deploy Functions and rules.
4. App Store Connect: set Sandbox Server Notifications V2 URL to the deployed function URL.
5. App Store Connect: create a Sandbox tester.
6. Xcode/TestFlight: install a build using the same Firebase project and bundle ID.
7. App: sign into PenPal Account A.
8. App/Firestore: app calls `getOrCreateAppAccountToken`.
   - Expected app behavior: purchases become available after token loads.
   - Expected Firestore: `users/{uid}/privateEntitlements/current.appAccountToken` exists and `appAccountTokens/{token}` maps to the UID.
9. App: buy Founder.
10. Backend: `processAppStoreTransaction` verifies signed transaction, validates bundle/product/appAccountToken, writes private entitlement, transaction indexes.
11. StoreKit: transaction finishes only after backend persistence succeeds.
12. App: private entitlement listener updates, Founder badge/PenPal Lab access appear.
13. Restart app.
14. App: Founder remains after backend entitlement reload.
15. App: tap Restore Purchases.
16. Backend: restore path processes current entitlements and calls `reconcileAppStoreEntitlements`.
17. Pass criteria: Founder access remains, no duplicate grant, no visible paid access before backend entitlement loads.

## 4. Minimum Premium Monthly Path

1. App Store Connect: confirm `PenPal Premium` subscription group exists.
2. App Store Connect: confirm `com.emily.penpal.premium.monthly` exists in that group.
3. Firebase/App: use the same deployed Sandbox setup as Founder.
4. App: sign into PenPal Account A with appAccountToken loaded.
5. App: purchase monthly Premium.
6. Backend: callable verifies transaction and writes:
   - `membershipTier: premium`
   - `premiumProductID: com.emily.penpal.premium.monthly`
   - `premiumStatus: active`
   - `premiumExpirationDate`
7. StoreKit: transaction finishes after backend persistence.
8. UI: Premium plan status appears only after private entitlement confirms.
9. Cancel auto-renew in Sandbox.
10. Expected: Premium stays active until Apple expiration; `premiumWillRenew` becomes false when notification/reconciliation observes it.
11. Let Sandbox subscription renew/expire according to Apple’s compressed Sandbox timings.
12. Expected: renewal advances expiration; expiration returns `membershipTier` to `free`; Founder state unchanged.

## 5. Firestore Inspection Checklist

Immediately after appAccountToken creation:

- `users/{uid}/privateEntitlements/current`
  - `schemaVersion: 1`
  - `membershipTier: free`
  - `isFounderSupporter: false`
  - `appAccountToken: <UUID>`
  - Premium fields null/none
- `appAccountTokens/{token}`
  - `uid`
  - `createdAt`
  - `updatedAt`

After callable purchase processing:

- `users/{uid}/privateEntitlements/current`
  - Founder: `isFounderSupporter: true`, Founder transaction fields set.
  - Premium: `membershipTier: premium`, product ID, expiration, status fields set.
- `appStoreOriginalTransactions/{environment}_{originalTransactionID}`
  - `uid`
  - `productKind`
  - `appAccountToken`
  - `environment`
- `appStoreTransactions/{environment}_{transactionID}`
  - `uid`
  - `productID`
  - `originalTransactionID`
  - `notificationType`
  - purchase/expiration/revocation dates
  - private signed transaction fields

After server notification processing:

- `appStoreNotificationEvents/{notificationUUID}`
  - `status: processed`, `skipped`, or `failed`
  - `notificationType`
  - `subtype`
  - `processedAt` when processed
- Entitlement document reflects renewal/cancellation/refund/expiration.

After restore:

- No new appAccountToken for the same PenPal user.
- Existing transaction bindings remain owned by the original UID.
- Entitlement document reflects Apple’s current state.

After renewal:

- New `appStoreTransactions/{environment}_{transactionID}`.
- Original transaction binding remains same.
- `premiumExpirationDate` advances.

After refund/revocation:

- Affected entitlement is removed only for that product domain.
- Founder revocation does not remove Premium.
- Premium revocation does not remove Founder.

Never client-readable:

- `appAccountTokens`
- `appStoreOriginalTransactions`
- `appStoreTransactions`
- `appStoreNotificationEvents`
- other users’ `privateEntitlements`

## 6. Function Logging and Troubleshooting

Current commerce logs do not log full signed JWS payloads or private keys. Commerce transaction JWS values are stored only in private server-owned `appStoreTransactions`, which Firestore rules deny to clients.

Recommended log commands:

```sh
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only getOrCreateAppAccountToken --lines 50
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only processAppStoreTransaction --lines 100
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only reconcileAppStoreEntitlements --lines 100
firebase functions:log --project "$FIREBASE_PROJECT_ID" --only appStoreServerNotificationsV2 --lines 100
```

Troubleshooting:

| Symptom | Likely cause | Check | Fix |
| --- | --- | --- | --- |
| Function fails immediately | Missing Firebase secret | Functions logs, secret list | Set all required `APPLE_*` secrets and redeploy. |
| Private key error | Malformed `.p8` secret | `APPLE_PRIVATE_KEY` value | Use `--data-file` with the unmodified `.p8`. |
| Root certificate error | Bad `APPLE_ROOT_CERTIFICATES_BASE64_JSON` | Function logs mention cert parse/verify | Recreate JSON array from Apple root certificates. |
| Production verification failure | Wrong `APPLE_APP_APPLE_ID` | App Store Connect app info | Set numeric app Apple ID. |
| Bundle mismatch | Wrong bundle ID in Apple/Xcode/backend | Code and App Store Connect | Ensure all use `com.emily.penpal`. |
| Unknown product | Product ID typo | App Store Connect products | Match exact product IDs. |
| Sandbox purchase rejected | Environment mismatch | Firebase secrets | Sandbox project must allow `Sandbox`. |
| appAccountToken mismatch | Purchase belongs to another PenPal UID | Firestore token and transaction bindings | Sign into correct PenPal account; do not transfer silently. |
| Transaction already linked | Same Apple purchase claimed by another UID | `appStoreOriginalTransactions` | Expected protection; use original PenPal account. |
| Firestore permission denied in app | Rules not deployed or wrong project | Firebase project/rules deploy | Deploy rules to the same project app uses. |
| Notification verification failed | Bad URL, environment, certs, or Apple payload | `appStoreServerNotificationsV2` logs | Correct URL/secrets/environment. |
| Product unavailable in StoreKit | Products not ready or wrong bundle/App Store account | App Store Connect and Sandbox tester | Finish product setup, use Sandbox Apple ID. |
| Transaction remains unfinished | Backend processing failed | App purchase result and function logs | Fix backend error, retry/restore. |
| Entitlement not updating | Listener/project mismatch or backend write failed | Firestore doc and app Firebase project | Confirm `GoogleService-Info.plist` project matches deployed project. |

## 7. Server Notification Validation

1. Deploy `appStoreServerNotificationsV2`.
2. Configure Sandbox URL in App Store Connect.
3. Use Apple’s Send Test Notification control if available.
4. Expected HTTP behavior:
   - Valid signed TEST payload returns 200.
   - Invalid/malformed payload returns 400.
5. Expected Firestore:
   - `appStoreNotificationEvents/{notificationUUID}` exists.
   - TEST without transaction may be `skipped` with a clear reason.
6. Redeliver if Apple tooling allows it.
   - Expected: duplicate event is not processed twice.
7. Check App Store Connect notification history.
8. Do not treat TEST as proof of lifecycle correctness. Lifecycle proof requires real subscription events: purchase, renewal, cancellation, expiration, refund/revocation where available.

## 8. Premium Lifecycle Test Order

1. Initial monthly purchase
   - StoreKit: verified transaction.
   - Backend: `membershipTier: premium`, status active.
   - UI: Premium active.
   - Founder unchanged.
2. Cancellation with paid access retained
   - Apple: renewal disabled, paid-through date remains.
   - Backend: Premium remains active, `premiumWillRenew: false` when observed.
3. Renewal
   - Apple: new transaction.
   - Backend: expiration advances.
4. Expiration
   - Apple: subscription expired.
   - Backend: `membershipTier: free`, Premium status expired.
5. Restore
   - Backend: reconciliation uses server-owned bindings and Apple server state.
6. Annual purchase
   - Backend: annual product maps to Premium.
7. Monthly-to-annual change
   - Backend: latest valid Premium state wins.
8. Billing retry
   - Backend: `premiumStatus: billingRetry`, UI should not claim stable active renewal.
9. Grace period
   - Backend: `premiumStatus: gracePeriod`, Premium remains active while Apple grants access.
10. Refund
   - Backend: Premium revoked/removed; Founder unchanged.
11. Duplicate notification
   - Backend: one notification event, no duplicate entitlement mutation.
12. Delayed notification
   - Backend: idempotent update from verified Apple state.
13. Reconciliation repair
   - Callable reconciliation restores backend state from server-owned original transaction IDs.

## 9. Founder and Premium Coexistence

Validate:

- Founder only: `isFounderSupporter: true`, `membershipTier: free`.
- Premium only: `isFounderSupporter: false`, `membershipTier: premium`.
- Founder then Premium: both true/premium.
- Premium then Founder: both true/premium.
- Premium expiration while Founder remains: `membershipTier: free`, `isFounderSupporter: true`.
- Founder refund/revocation while Premium remains: `isFounderSupporter: false`, Premium state unchanged.
- Restore when both are owned: both restored only for original PenPal account.
- Account switching: Apple ID ownership does not transfer to a different PenPal account.

The backend entitlement write merges independent domains. Founder transactions update Founder fields while preserving current Premium state. Premium transactions update Premium fields while preserving current Founder state.

## 10. TestFlight Readiness

After Sandbox passes:

- App Store Connect products must be configured and ready for review/testing.
- First IAPs usually need to be submitted with an app version for App Review.
- Review screenshots and notes must explain Founder non-consumable and Premium subscription.
- TestFlight purchases still use Sandbox Apple purchase infrastructure.
- If TestFlight points at the production Firebase project, decide deliberately whether that project should allow Sandbox transactions. Prefer a separate Firebase project for TestFlight/Sandbox.
- Confirm the app build uses the intended `GoogleService-Info.plist`.
- Confirm production UI uses StoreKit prices from Apple, not local `.storekit` fake prices.
- Confirm localized prices display for Founder/monthly/annual.
- Test restore on a second physical device.
- Confirm notification URL environment matches the deployed Firebase project.

## 11. Final Release Gate

Commerce is **NOT READY** until all boxes are checked:

- [ ] Functions deployed.
- [ ] Firestore rules deployed.
- [ ] Real Apple credentials loaded as Firebase secrets.
- [ ] Products available from StoreKit.
- [ ] `appAccountToken` created.
- [ ] Founder Sandbox purchase verified.
- [ ] Founder entitlement persisted.
- [ ] Founder transaction finished.
- [ ] Founder restore passed.
- [ ] Premium Sandbox purchase verified.
- [ ] Premium entitlement persisted.
- [ ] Premium transaction finished.
- [ ] Cancellation behavior passed.
- [ ] Renewal or accelerated Sandbox renewal passed.
- [ ] Expiration behavior passed.
- [ ] Founder/Premium coexistence passed.
- [ ] Account-switch ownership protection passed.
- [ ] Real V2 notification verified.
- [ ] Duplicate notification handling passed.
- [ ] Reconciliation passed.
- [ ] TestFlight purchase passed.
- [ ] TestFlight restore passed.
