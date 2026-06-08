# Product model

BlitzRecorder launches as a direct-download, open-source Mac recorder with a
paid Early Lifetime License for the full studio.

## Products

- **BlitzRecorder for macOS**: standalone recording app. The free tier records
  screen, Mac camera, microphone, scenes, and 1080p exports with no account,
  watermark, subscription, or card requirement.
- **Early Lifetime License**: one-time Stripe purchase that unlocks iPhone
  camera recording, 4K export, and 60 fps export in the direct-download Mac app.
  Early buyers keep the "all your personal Macs" deal.
- **BlitzRecorder Camera for iPhone**: free companion input app. It has no
  checkout or paywall inside the iOS app, but the Mac app must have an active
  Early Lifetime License to use the iPhone camera source.
- **BlitzReels**: separate optional product for turning existing footage into
  clips. It does not unlock recorder features.

## Pricing

- Free Mac tier: `$0`
- Early Lifetime License: `$39`, planned to become `$79` after launch
- iPhone companion app: `$0`

## Access

The direct-download Mac app validates BlitzRecorder license keys against
`https://blitzrecorder.com/api/licenses/validate`. Stripe remains the payment
source of truth, and an optional Postgres license store enables revocation,
refund/dispute handling, and customer support queries.

The app does not use StoreKit, BlitzReels sign-in, subscriptions, or export
counters to unlock the direct-download paid features.

## Distribution

Launch distribution is the Developer ID signed, notarized DMG from the website
and GitHub Releases. That build includes Sparkle for updates.

Mac App Store distribution is paused for this launch because Mac App Store apps
cannot use Sparkle or custom license-key copy protection. If a Mac App Store
build ships later, it needs a separate StoreKit/App Store product model.
