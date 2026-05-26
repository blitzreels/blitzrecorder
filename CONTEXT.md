# BlitzRecorder Context

## Domain Language

- **Capture Source**: A user-enabled input that can contribute media to a take. Current capture sources are Screen, Camera, System Audio, and Microphone.
- **Camera Provider**: A way to supply the Camera capture source. Current provider families are Local Camera, Continuity Camera, Desk View, External Camera, and Remote iPhone Camera.
- **Local Camera**: A Mac-visible camera provider captured directly by BlitzRecorder.
- **Continuity Camera**: Apple's built-in iPhone-as-webcam camera provider, captured by BlitzRecorder as a Mac-visible camera with system-managed iPhone behavior.
- **Remote iPhone Camera**: A camera provider where the BlitzRecorder iPhone companion app owns capture on the iPhone while the Mac app controls and monitors it.
- **Camera Transport**: The connection path used between the Mac app and a Remote iPhone Camera.
- **Local Network Camera Transport**: A Camera Transport over the user's local network.
- **Wired Camera Transport**: A Camera Transport over a direct cable connection when available.
- **Remote Camera Transfer**: The stop-time and recovery workflow that imports the Master Camera Recording from a Remote iPhone Camera into the Take, including transfer readiness, resumable chunks, acknowledgements, checksum validation, manifest writing, and pending import recovery.
- **Master Camera Recording**: The authoritative camera media for a take.
- **Monitor Preview**: A live, lower-latency camera view used for framing and confidence while recording.
- **Permission Gate**: The pre-recording check that decides whether the enabled capture sources can start recording.
- **Take**: One recording session directory containing the selected source files and any derived transcript/title files.
- **Take Timeline**: The authoritative timing basis for all source files in a take.
- **Capture Source Run**: The active set of Capture Sources writing media for one Take, including source startup, pause/resume, stop, and per-source media completion.
- **Capture Source Stop Failure**: A stop-time failure from one Capture Source. It should be reported with the Capture Source Run summary without discarding media already completed by other Capture Sources.
- **Take Finalization**: The post-stop workflow that turns a Take into a saved final video or a recoverable Take directory.
- **Media Writer Completion**: The stop-time result from a writer that says whether media samples were actually written.
- **Preview Stage**: The live canvas showing the selected screen source and camera inset before recording.
- **Scene Layout**: The normalized Preview Stage description for video source frames and back-to-front layer order. It is the source of truth for live composition and final export placement.
- **Recording Scene**: The live-composition state derived from Scene Layout plus video source visibility, camera crop, canvas background, and canvas padding. It can change during a live-composited Take without changing the Take Timeline, capture devices, output format, or output dimensions.
- **Scene Render Geometry**: The pixel-space projection of a Recording Scene into a concrete output canvas, including per-source target rectangles, camera crop placement, padding, and padding-derived corner masks. Monitor Preview, live composition, and final export should share this geometry instead of recomputing it independently.
- **Picked Screen Content**: A screen, window, or app selected through Apple's `SCContentSharingPicker`. This is session-scoped user consent and should bypass the broad Screen Recording gate for the screen source only.

## macOS TCC Notes

- Broad screen capture is governed by `kTCCServiceScreenCapture`; local logs showed `Service kTCCServiceScreenCapture does not allow prompting; returning denied.`
- Camera and microphone use normal promptable AVFoundation authorization. Screen capture does not behave the same way.
- TCC grants are tied to app identity: bundle id, code signature, and app location. Use `/Applications/BlitzRecorder.app` via `script/build_and_run.sh` for local testing.
- `SCShareableContent` remains useful for display enumeration and broad capture, but it requires Screen & System Audio Recording approval in System Settings.
- `SCContentSharingPicker` is the preferred low-friction local path because the user explicitly selects content and macOS permits that selected capture session.
- System audio still requires the broad Screen & System Audio Recording permission path.
