# Product model

BlitzRecorder is a free, open-source recorder. BlitzRecorder Camera for iPhone is a free companion input app.

## Products

- **BlitzRecorder for macOS**: standalone recording app with no export limit, account requirement, watermark, in-app purchase, or subscription gate.
- **BlitzRecorder Camera for iPhone**: free companion camera app with no paywall and no in-app purchases.
- **BlitzReels**: separate optional product for turning existing footage into clips. It does not unlock recorder features.

## Pricing

- Mac app: `$0`
- iPhone companion: `$0`
- Paid tier: none

## Access

All recorder features are available by default. The app does not use StoreKit, BlitzReels sign-in, export counters, or remote entitlement checks to decide whether a user can record or export.

Legacy purchase, free-export, or BlitzReels entitlement state may remain on a user's machine from older builds, but it must not block access.

## Distribution

Official signed builds, GitHub releases, and App Store/TestFlight packaging can still exist as distribution channels. They must not introduce a Pro tier or feature lock without an explicit product decision.
