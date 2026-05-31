# BlitzRecorder Privacy Nutrition Labels

Draft App Store Connect worksheet. Confirm final answers in App Store Connect with legal/privacy review before submission.

## Shared Principles

- Tracking: No.
- Third-party advertising: No.
- Data broker sharing: No.
- Recordings are local by default and are not uploaded to BlitzReels or BlitzRecorder servers by the apps.
- Local network traffic between Mac and iPhone is device-to-device app functionality, not developer collection.
- App Store purchases are handled by Apple StoreKit. The app reads entitlement state locally.
- Support data is only received if the user contacts support and chooses what to send.

## macOS App: BlitzRecorder

Bundle ID: `dev.blitzreels.blitzrecorder`

Recommended App Store Connect answer:

- Data Used to Track You: No
- Data Linked to You: Yes, only when the user signs in with BlitzReels for included access
- Data Not Linked to You: No app analytics or diagnostics collected by the app

### Collected Data Types

| App Store Category | Data Type | Collected? | Linked to User? | Tracking? | Purpose | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Identifiers | User ID | Yes, conditional | Yes | No | App Functionality | BlitzReels sign-in returns an access token. The app stores it in macOS Keychain and sends it to the BlitzReels entitlement endpoint only to verify included Pro access. |
| Purchases | Purchase History | No by BlitzRecorder | No | No | App Functionality | StoreKit handles App Store subscription state. Do not mark this collected unless BlitzRecorder starts sending transaction or receipt details to a developer server. |
| User Content | Photos or Videos | No | No | No | App Functionality | Screen/camera recordings are saved locally to user-selected folders. |
| User Content | Audio Data | No | No | No | App Functionality | Microphone/system audio recordings are saved locally to user-selected folders. |
| Diagnostics | Crash Data / Performance Data | No | No | No | App Functionality | No crash or analytics SDK is currently integrated. |
| Usage Data | Product Interaction | No | No | No | App Functionality | Export counts and settings are stored locally in UserDefaults. |
| Contact Info | Email Address | No in app | No | No | Customer Support | Support may receive email only if the user contacts support outside the app flow. |

### Required Permission Explanations

- Camera: records the selected local camera source.
- Microphone: records selected microphone audio and may support local transcription-based file naming.
- Screen/System Audio Recording: records selected screen/system audio sources.
- Speech Recognition: supports local transcription-based file naming.
- Local Network / Bonjour: discovers and pairs with BlitzRecorder Camera on iPhone or iPad.
- User-selected file access: saves recordings and exports in the output folder the user chooses.

### Current Privacy Manifest

Bundled file: `Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy`

- `NSPrivacyTracking`: `false`
- `NSPrivacyCollectedDataTypes`: empty
- Required-reason APIs:
  - `NSPrivacyAccessedAPICategoryUserDefaults`
  - `NSPrivacyAccessedAPICategoryFileTimestamp`

## iOS App: BlitzRecorder Camera

Bundle ID: `dev.blitzreels.blitzrecorder.camera`

Recommended App Store Connect answer:

- Data Used to Track You: No
- Data Linked to You: No
- Data Not Linked to You: No
- Data Collected: No

### Collected Data Types

| App Store Category | Data Type | Collected? | Linked to User? | Tracking? | Purpose | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| User Content | Photos or Videos | No | No | No | App Functionality | Camera recordings are stored locally on the iPhone/iPad and transferred to the paired Mac over the local network. |
| Diagnostics | Crash Data / Performance Data | No | No | No | App Functionality | No crash or analytics SDK is currently integrated. |
| Usage Data | Product Interaction | No | No | No | App Functionality | Device ID and pairing state are stored locally in UserDefaults. |
| Identifiers | Device ID | No | No | No | App Functionality | The locally generated companion device ID is used for pairing and local network discovery, not collected by the developer. |

### Required Permission Explanations

- Camera: captures the iPhone/iPad camera source selected by the user.
- Local Network / Bonjour: pairs with the Mac, sends monitor preview and camera telemetry, receives camera controls, and transfers local camera recordings.
- Microphone: can include iPhone microphone audio in the source camera file when recording starts.

### Current Privacy Manifest

Bundled file: `Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy`

- `NSPrivacyTracking`: `false`
- `NSPrivacyCollectedDataTypes`: empty
- Required-reason APIs:
  - `NSPrivacyAccessedAPICategoryUserDefaults`
  - `NSPrivacyAccessedAPICategoryFileTimestamp`
  - `NSPrivacyAccessedAPICategoryDiskSpace`

## Review Before Submission

- If analytics, crash reporting, logging upload, customer support upload, receipt validation, or account telemetry is added later, update this worksheet before upload.
- If BlitzReels entitlement verification starts returning or storing email, Stripe IDs, workspace IDs, or subscription IDs in the app, update the macOS label beyond `Identifiers / User ID`.
- If recordings, thumbnails, transcripts, or logs are uploaded for any app feature, add the corresponding User Content, Audio Data, Diagnostics, or Other Data categories.
- Keep this worksheet aligned with `Web/blitzrecorder/src/main.jsx`, `AppStore/Metadata-macOS.md`, `AppStore/Metadata-iOS.md`, and the bundled privacy manifests.
