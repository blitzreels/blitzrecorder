# Architecture

BlitzRecorder is a small native Apple monorepo with a macOS recorder app, an iOS companion camera app, and shared Swift packages for remote camera models and transport.

## Workspace layout

- `Sources/BlitzRecorderApp`: macOS recorder app
- `Apps/iOSCamera`: iPhone companion camera app
- `Packages/BlitzRecorderCore`: shared remote-camera protocol models
- `Packages/BlitzRecorderTransport`: Bonjour discovery, advertising, framing, and JSON message utilities
- `project.yml`: XcodeGen project specification
- `Scripts/`: local validation, packaging, App Store, and CI helper scripts
- `AppStore/`: metadata, privacy labels, review notes, and submission checklists

## Core concepts

- **Capture source**: an enabled input that can contribute media to a take, such as screen, camera, system audio, or microphone.
- **Take**: one recording session with source media, transcript output, and final export state.
- **Take timeline**: the timing basis that aligns source media and removes pause gaps.
- **Scene layout**: the normalized source placement used by preview and final export.
- **Remote iPhone camera**: an iPhone companion device that records the camera master locally while the Mac coordinates the take.
- **Monitor preview**: a live lower-latency iPhone preview used for framing, not as final camera media.

## Apple-native stack

BlitzRecorder is intentionally native rather than Electron, Tauri, or Catalyst. The app needs direct access to ScreenCaptureKit, AVFoundation, StoreKit, VideoToolbox, and Apple's privacy model.

The macOS app uses SwiftUI for most product UI and AppKit where macOS still requires it, including window/status item integration and preview-stage hosting. The iOS companion uses SwiftUI and AVFoundation.

## Remote iPhone camera

The Mac remains the take coordinator and timeline authority. The iPhone owns camera capture, records the master camera file locally, streams monitor preview, accepts Mac camera controls, and transfers completed media back to the Mac.

The v1 transport is local network based with Bonjour discovery. The protocol is isolated in shared packages so wired or alternate transports can reuse the same product behavior later.

## AI and transcription

BlitzRecorder currently supports post-recording transcription and transcript-derived title generation. Local title generation can use small Ollama models when available, with a fallback slugger when local model generation is unavailable.

Future Apple-native candidates include Foundation Models and newer SpeechTranscriber APIs when the deployment target and product requirements are ready for them.
