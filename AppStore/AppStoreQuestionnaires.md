# BlitzRecorder App Store Questionnaires

Last updated: 2026-05-22

Use this worksheet when App Store Connect asks for age rating, export compliance, content rights, advertising identifier, and related release questions. Confirm final answers with legal review before submission.

## Age Rating

Recommended rating target: `4+`

Suggested questionnaire answers for both app records:

| Category | Suggested Answer | Rationale |
| --- | --- | --- |
| Cartoon or fantasy violence | None | The apps do not include built-in violent content. |
| Realistic violence | None | The apps do not include built-in violent content. |
| Prolonged graphic or sadistic realistic violence | None | Not present. |
| Profanity or crude humor | None | Not present in app-provided content. |
| Mature or suggestive themes | None | Not present in app-provided content. |
| Horror/fear themes | None | Not present in app-provided content. |
| Medical/treatment information | None | Not present. |
| Alcohol, tobacco, drug use or references | None | Not present in app-provided content. |
| Simulated gambling | None | Not present. |
| Sexual content or nudity | None | Not present in app-provided content. |
| Contests | No | The apps do not run contests. |
| Gambling | No | The apps do not enable gambling. |
| Unrestricted web access | No | The Mac app opens fixed BlitzRecorder legal/support/sign-in URLs and Apple subscription management; it does not provide a general browser. |
| User-generated content | No for app-provided service content | Users create local recordings, but the apps do not host, publish, browse, moderate, or share user-generated content through a developer service. |

Notes:

- The user can record arbitrary on-device content, but that content is user-controlled and local by default.
- If future releases add hosting, sharing, browsing, comments, public galleries, or community features, revisit age rating and user-generated content answers.

## Export Compliance / Encryption

Current implementation:

- macOS `Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`.
- iOS companion `Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`.
- The apps use Apple system networking and HTTPS for fixed BlitzRecorder/BlitzReels URLs.
- The iPhone companion uses local network transport for pairing, monitor preview, camera controls, and file transfer.
- CryptoKit SHA-256 is used only for file-transfer integrity checks, not for encryption or decryption.
- The Mac app stores the BlitzReels access token in the macOS Keychain.
- There is no proprietary encryption, custom cryptographic protocol, VPN, encrypted messaging, DRM, cryptocurrency wallet, password manager, or security product functionality.

Recommended App Store Connect answer:

- Uses encryption: answer according to the current App Store Connect wording, with the intended result that no non-exempt encryption filing is required.
- Export compliance status: no non-exempt encryption.

Evidence:

- `Info.plist`: `ITSAppUsesNonExemptEncryption = false`
- `Apps/iOSCamera/Info.plist`: `ITSAppUsesNonExemptEncryption = false`
- `Sources/BlitzRecorderApp/RecorderCoordinator.swift`: SHA-256 transfer digest verification only
- `Apps/iOSCamera/Sources/CameraCompanionStore.swift`: SHA-256 transfer digest generation only

## Content Rights

Recommended answer:

- The apps do not ship third-party media catalogs, templates, music libraries, stock footage, or externally licensed editorial content for end users to publish.
- Users are responsible for rights to screens, audio, video, meetings, software, music, or other content they record.
- Terms page includes user-content responsibility language.

Evidence:

- `Web/blitzrecorder/src/main.jsx`
- `AppStore/Metadata-macOS.md`
- `AppStore/Metadata-iOS.md`

## Advertising Identifier

Recommended answer:

- Does the app use IDFA? `No`
- Tracking: `No`
- Third-party advertising: `No`

Evidence:

- No advertising SDK is integrated.
- Privacy manifests declare `NSPrivacyTracking = false`.
- `AppStore/PrivacyNutritionLabels.md` marks tracking as `No`.

## Kids Category

Recommended answer:

- Made for Kids: `No`

Rationale:

- BlitzRecorder is a creator/productivity recording tool, not a child-directed app.
- The direct-download product has no subscription purchase flow. It uses a one-time Stripe license outside the Mac App Store.

## Sign-In Requirement

Recommended answer:

- No sign-in is required to record or export.
- BlitzReels sign-in is not used as a recorder entitlement gate.
- The iOS companion app does not require an account; pairing is local-network based.

## Paid Content And Subscriptions

Recommended answer:

- Mac app has auto-renewable subscriptions: No
- Monthly product ID: none
- Monthly price: `$0`
- Annual product ID: none
- Annual price: `$0`
- Free behavior: 1080p Mac recording/export
- Paid behavior: direct-download Early Lifetime License unlocks iPhone camera, 4K export, and 60 fps export
- iOS companion has no in-app purchases and no paywall; App Review notes must explain that the Mac app license is sold on blitzrecorder.com for the direct-download launch.

## Review Before Submission

Recheck this worksheet if any of the following changes before submission:

- Analytics, crash reporting, ads, attribution, or tracking SDKs are added.
- Cloud upload, sharing, hosting, collaboration, comments, public profiles, or publishing are added.
- End-user templates, music, stock footage, or other bundled third-party media are added.
- Custom encryption, encrypted messaging, VPN/security, DRM, crypto wallet, or password-management functionality is added.
- Account, purchase, entitlement, analytics, or cloud upload flows are added.
