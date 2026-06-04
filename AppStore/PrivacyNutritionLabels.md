# BlitzRecorder Privacy Nutrition Labels

Draft App Store Connect worksheet. Confirm final answers in App Store Connect with legal/privacy review before submission.

## Shared Principles

- Tracking: No.
- Third-party advertising: No.
- Data broker sharing: No.
- Recordings are local by default and are not uploaded to BlitzReels or BlitzRecorder servers by the apps.
- Local network traffic between Mac and iPhone is device-to-device app functionality, not developer collection.
- The apps do not require an account, purchase, subscription, or entitlement check.
- Support data is only received if the user contacts support and chooses what to send.
- The Mac app can copy a local diagnostics report to the clipboard from the Help menu. Nothing is uploaded automatically.

## macOS App: BlitzRecorder

Bundle ID: `dev.blitzreels.blitzrecorder`

Recommended App Store Connect answer:

- Data Used to Track You: No
- Data Linked to You: No
- Data Not Linked to You: No app analytics or diagnostics collected by the app

### Collected Data Types

| App Store Category | Data Type | Collected? | Linked to User? | Tracking? | Purpose | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Identifiers | User ID | No | No | No | App Functionality | No account is required to record or export. |
| Purchases | Purchase History | No | No | No | App Functionality | No in-app purchases or subscriptions are required to record or export. |
| User Content | Photos or Videos | No | No | No | App Functionality | Screen/camera recordings are saved locally to user-selected folders. |
| User Content | Audio Data | No | No | No | App Functionality | Microphone/system audio recordings are saved locally to user-selected folders. |
| Diagnostics | Crash Data / Performance Data | No | No | No | App Functionality | No crash or analytics SDK is currently integrated. Help -> Copy Diagnostics creates a local clipboard report only. |
| Usage Data | Product Interaction | No | No | No | App Functionality | Settings are stored locally in UserDefaults. |
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

- If analytics, crash reporting, automatic logging upload, receipt validation, or account telemetry is added later, update this worksheet before upload.
- If support starts receiving diagnostics through an in-app upload instead of user-copied text, update the Diagnostics row before upload.
- If account, purchase, entitlement, analytics, or cloud upload flows are added later, update the macOS labels before submission.
- If recordings, thumbnails, transcripts, or logs are uploaded for any app feature, add the corresponding User Content, Audio Data, Diagnostics, or Other Data categories.
- Keep this worksheet aligned with `Web/blitzrecorder/src/main.jsx`, `AppStore/Metadata-macOS.md`, `AppStore/Metadata-iOS.md`, and the bundled privacy manifests.
