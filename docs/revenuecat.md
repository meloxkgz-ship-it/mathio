# RevenueCat setup for Mathio

Mathio is wired for RevenueCat through the iOS SDK. The app still keeps its
StoreKit 2 fallback when no RevenueCat public SDK key is configured, so local
screenshots and reviewer override continue to work.

## App identifiers

- Bundle ID: `com.kgz.Mathio`
- App Store Connect app ID: `6767033115`
- RevenueCat project ID: `a4d57e90`
- RevenueCat App Store app ID: `appcfdadb3b91`
- RevenueCat entitlement IDs accepted by the app: `premium` or `plus`
- App Store subscription group: `Premium` (`22071889`)

## Products

These App Store products are imported into the RevenueCat App Store app and
attached to the `premium` entitlement:

| Product ID | App Store subscription ID | RevenueCat package | App Store state | Purpose |
| --- | --- | --- | --- | --- |
| `mathio_annual` | `6767033716` | Annual | `APPROVED` | Primary yearly subscription |
| `mathio_weekly` | `6767033995` | Weekly | `APPROVED` | Weekly subscription |
| `mathio_retention` | `6767033879` | Custom | `APPROVED` | Retention yearly discount |

Verified with `asc subscriptions list --group-id 22071889` on 2026-05-23.

Default offering `default` (`ofrng2e6dec0fa8`) packages:

| Package identifier | RevenueCat package | Product ID |
| --- | --- | --- |
| `$rc_weekly` | Weekly | `mathio_weekly` |
| `$rc_annual` | Annual | `mathio_annual` |
| `retention` | Custom | `mathio_retention` |

## SDK key

Only use the iOS public SDK key from RevenueCat. Do not commit secret API keys.
The Mathio App Store configuration uses public SDK key
`appl_lVxesEhigXwlheVPosBJrNbIXyE`.

The key is stored in the Xcode build setting `REVENUECAT_API_KEY`. You can still
override it at build time:

```bash
xcodebuild \
  -project iOS/Mathio/Mathio.xcodeproj \
  -scheme Mathio \
  REVENUECAT_API_KEY=appl_your_public_key_here
```

The build setting is copied into `RevenueCatAPIKey` in the app Info.plist.
If the key is empty, missing, a placeholder, or not an `appl_` key, the app uses
the legacy StoreKit path instead of configuring RevenueCat.

Before uploading a RevenueCat-enabled release build, run:

```bash
docs/aso/scripts/verify_revenuecat_release.sh \
  ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release-iphoneos/Mathio.app
```

The preflight fails if the key is missing, is not an iOS public SDK key, still
looks like a placeholder, or was not copied into the built app's Info.plist.

RevenueCat's current setup docs require configuring the SDK once with the
platform public SDK key, and the dashboard must contain products, entitlements,
and offerings before the SDK can serve purchases. See RevenueCat's iOS
installation, SDK configuration, quickstart, and Apple app privacy docs:

- https://www.revenuecat.com/docs/getting-started/installation/ios
- https://www.revenuecat.com/docs/getting-started/configuring-sdk
- https://www.revenuecat.com/docs/getting-started/quickstart
- https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy

## Runtime behavior

- App launch configures RevenueCat once when a public SDK key is present.
- Premium unlock checks RevenueCat customer info for `premium` or `plus`.
- Paywall prices come from RevenueCat offerings first, then StoreKit fallback.
- Purchases use `purchase(package:)` when RevenueCat is enabled.
- Restore uses `restorePurchases()` when RevenueCat is enabled.
- The existing seven-tap reviewer override remains available for App Review.
