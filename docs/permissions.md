# Permissions

BlitzRecorder records only user-selected sources, but macOS treats screen capture differently from camera and microphone capture.

## macOS Camera and Microphone

Camera and microphone access use standard AVFoundation permission prompts. Users can grant or revoke access in System Settings.

## Screen Capture

BlitzRecorder supports two screen paths:

- **Pick Screen...**: uses Apple's `SCContentSharingPicker`. The user explicitly selects a screen, window, or app, and macOS grants that selected capture session.
- **Display picker**: uses programmatic ScreenCaptureKit display capture. This path requires broad Screen & System Audio Recording permission in System Settings.

System audio also uses the broad Screen & System Audio Recording permission path.

Local testing showed macOS does not reliably allow an app prompt for broad screen capture. If broad display capture fails, enable BlitzRecorder manually under:

```text
System Settings -> Privacy & Security -> Screen & System Audio Recording
```

Then fully quit and reopen the app.

## App Identity and TCC

macOS privacy grants are tied to app identity: bundle id, code signature, and app location. Renaming the app, changing the bundle id, switching between debug and installed copies, or rebuilding with a different signature can make macOS treat it as a different app.

For local testing, use:

```bash
./script/build_and_run.sh --verify
```

That installs and launches `/Applications/BlitzRecorder.app` with a stable identity.

## iPhone Companion

BlitzRecorder Camera asks for:

- Camera access to record the iPhone camera source
- Microphone access when source camera audio is included
- Local network access for pairing, monitor preview, controls, and file transfer

The iPhone app records the camera master locally first, then transfers the completed file to the paired Mac.

## BlitzReels Included Access

Normal App Store customers do not need a BlitzRecorder account. If a user chooses BlitzReels included access, the Mac app opens BlitzReels sign-in, receives a callback token, stores it in the macOS Keychain, and uses it only to verify the included Pro entitlement.
