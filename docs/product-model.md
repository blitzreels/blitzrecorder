# Product model

BlitzRecorder is the paid recording product in the BlitzReels family. BlitzRecorder Camera for iPhone is a free companion input app.

## Products

- **BlitzRecorder for macOS**: standalone recording app and the only app that sells Pro access.
- **BlitzRecorder Camera for iPhone**: free companion camera app with no paywall and no in-app purchases.
- **BlitzReels**: separate product. Eligible active BlitzReels subscribers can unlock BlitzRecorder Pro as an included benefit.

## Pricing

- Free: 3 finished exports
- Pro monthly: `$7.99/month`
- Pro annual: `$49.99/year`
- BlitzReels bundle: included for eligible active BlitzReels subscribers

The iPhone app stays free because it is a companion input device for the Mac recorder, not a standalone paid camera product.

## Entitlements

The Mac app supports two Pro entitlement paths:

1. **App Store subscription**: the Mac app sells, restores, and verifies BlitzRecorder Pro monthly and annual subscriptions through StoreKit. StoreKit entitlement state unlocks unlimited Mac exports.
2. **BlitzReels included access**: the Mac app opens BlitzReels sign-in only when the user wants to unlock included access from an existing BlitzReels subscription. BlitzReels redirects back to `blitzrecorder://auth/blitzreels?token=<access-token>`. The Mac app stores that token in the macOS Keychain and calls the BlitzReels entitlement endpoint. An active response unlocks Pro.

The iPhone companion does not sell, restore, or verify subscriptions. It pairs locally with the Mac app and lets the Mac enforce export entitlement.

## Distribution scope

Launch licensing is bound to the App Store channel. Do not add LemonSqueezy, Paddle, Stripe license keys, custom device activation limits, or a separate BlitzRecorder account system to the App Store build.

A direct-download Mac app could add separate licensing later as its own distribution channel, but it is intentionally out of scope for the App Store version.
