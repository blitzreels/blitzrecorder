# PRD: Remote iPhone Camera

Date: 2026-05-22
Status: Draft
Owner: BlitzRecorder

## Summary

Build a SwiftUI iPhone companion app that turns supported iPhones into a fully controlled remote camera provider for BlitzRecorder. The Mac app remains the take coordinator and timeline authority. The iPhone owns camera capture, records the master camera file locally, streams a live monitor preview to the Mac, accepts camera controls from the Mac, and transfers the master camera recording into the take after recording.

This feature extends the existing **Camera** capture source. It does not add a new top-level capture source.

## Goals

- Let creators use supported iPhones, especially Pro models, as professional camera inputs for BlitzRecorder.
- Target iOS 26.0 or later for the iPhone companion app, built with the current Xcode 26 / iOS 26 SDK.
- Support Mac-triggered, Mac-synchronized recording while preserving iPhone-local recording reliability.
- Provide live monitor preview in the Mac app for framing and confidence.
- Provide meaningful iPhone camera controls from the Mac app: lens, zoom, focus, exposure, white balance, frame rate, resolution, stabilization, torch, and supported format selection.
- Transfer the iPhone master camera recording into the existing take folder so export and scene layout continue to work through the existing Camera source.
- Support production-grade local network transport for v1.
- Target wired camera transport as best effort for v1 when available through Apple-supported networking paths.

## Non-Goals

- Do not replace Continuity Camera. Continuity Camera remains available as a lower-control Apple-managed camera provider.
- Do not depend on the live monitor preview as the final camera recording.
- Do not require USB data transport to ship v1.
- Do not promise Apple's system Portrait video effect as an app-controlled toggle. If portrait-like capture is needed, treat it as future custom processing.
- Do not build a general-purpose livestreaming product or OBS replacement.

## Domain Terms

- **Camera**: Existing BlitzRecorder capture source used in the take and scene layout.
- **Remote iPhone Camera**: Camera provider where the iPhone companion app owns capture while the Mac app controls and monitors it.
- **Master Camera Recording**: Authoritative camera media recorded locally on iPhone.
- **Monitor Preview**: Lower-latency live camera stream displayed in the Mac app.
- **Take Timeline**: Mac-authoritative timing basis for all source files in a take.
- **Camera Transport**: Connection path between Mac and Remote iPhone Camera.
- **Local Network Camera Transport**: Wi-Fi/LAN path used for v1 guaranteed support.
- **Wired Camera Transport**: Direct cable path, supported best effort when available.

## User Experience

### Pairing

1. User opens BlitzRecorder on Mac.
2. User opens the BlitzRecorder Camera companion app on iPhone.
3. The Mac discovers available iPhones over Bonjour/local network.
4. User explicitly pairs with the iPhone using a confirmation prompt or short code.
5. The paired iPhone appears in the existing Camera picker as a Remote iPhone Camera.

The Mac must never auto-connect to an arbitrary nearby iPhone.

### Recording

1. User selects the Remote iPhone Camera in the Camera picker.
2. Mac shows the iPhone monitor preview in the existing Preview Stage camera layer.
3. User adjusts supported camera controls from the Mac.
4. User presses Record in the Mac app.
5. Mac prepares all enabled capture sources.
6. Mac sends prepare/start commands to iPhone and synchronizes the iPhone recording to the Mac Take Timeline.
7. iPhone records the Master Camera Recording locally.
8. iPhone streams Monitor Preview to the Mac during recording.
9. User presses Stop in the Mac app.
10. iPhone stops local recording and transfers the master file to the Mac.
11. Mac stores the transferred file as the take's camera media and proceeds with existing post-recording behavior.

### iPhone UI

The companion app must clearly show:

- paired Mac name
- connection state
- recording state
- elapsed recording time
- selected lens/format
- battery level
- thermal warning state when relevant
- storage remaining or estimated remaining recording time
- local Stop button during active recording

The iPhone app must remain useful without looking at the Mac, because it is the fallback control surface if the Mac disconnects.

## Functional Requirements

### Mac App

- Discover Remote iPhone Camera devices using Network.framework/Bonjour.
- Pair only after explicit user confirmation.
- Persist trusted paired devices.
- Show paired devices in the existing Camera picker.
- Display Monitor Preview in the existing camera layer of the Preview Stage.
- Route Remote iPhone Camera media through the existing Camera capture source and Scene Layout behavior.
- Provide camera controls based on iPhone-reported capabilities.
- Coordinate recording start/stop against the Mac Take Timeline.
- Receive recording metadata from the iPhone: start timestamp, stop timestamp, duration, format, lens, frame rate, resolution, transfer status.
- Align transferred camera media to the Take Timeline.
- Show degraded state when monitor preview or control channel disconnects.
- Resume monitor preview after reconnect without restarting the iPhone recording.
- Import pending iPhone recordings after reconnect.

### iPhone Companion App

- Be built with SwiftUI.
- Require iOS 26.0 or later.
- Own all iPhone camera capture through AVFoundation.
- Report supported camera capabilities to the Mac.
- Support supported lens selection, including ultra-wide, wide, and telephoto where hardware allows.
- Record the Master Camera Recording locally on iPhone.
- Stream a lower-latency Monitor Preview to the Mac while recording.
- Accept Mac commands for prepare, start, stop, camera settings, and transfer.
- Keep recording if the Mac disconnects.
- Never auto-stop solely because the Mac disconnects.
- Allow user-initiated stop on iPhone.
- Preserve pending recordings after disconnect or app relaunch when possible.
- Transfer completed recordings to the Mac when connected.

### Transport

- v1 must support Local Network Camera Transport.
- v1 should attempt Wired Camera Transport when Apple-supported Network.framework paths are available.
- Camera controls, monitor preview, telemetry, and file transfer must use a transport abstraction so Wi-Fi/LAN and wired paths share the same product behavior.
- Transport must tolerate connection loss during active recording.
- Discovery must use Bonjour/local network declarations and clear local network permission strings.
- Manual pairing fallback should be available when Bonjour discovery fails but direct network reachability exists.

### Camera Controls

The Mac control panel should expose only controls supported by the active iPhone, lens, and format.

Required v1 controls:

- lens selector
- zoom factor and zoom ramp
- resolution and frame rate
- focus mode
- manual focus position when supported
- exposure mode
- exposure bias
- manual ISO/shutter where supported
- white balance mode
- manual white balance where supported
- stabilization mode where supported
- torch where supported

Telemetry:

- battery
- thermal state
- storage remaining
- active lens
- active format
- recording elapsed time
- preview connection state
- transfer progress
- dropped preview frames or preview health indicator

## Failure Behavior

### Monitor Preview Disconnects

- iPhone continues recording the Master Camera Recording.
- Mac continues recording other enabled capture sources.
- Mac camera tile shows a degraded monitor state.
- Mac retries preview connection.
- If preview reconnects, it resumes without restarting recording.

### Control Channel Disconnects

- iPhone continues recording.
- iPhone shows "Mac disconnected" or equivalent.
- User may stop recording from iPhone.
- Mac attempts reconnect.
- On reconnect, Mac reconciles state and imports pending recording if needed.

### Mac App Crashes or Sleeps

- iPhone continues recording.
- iPhone does not auto-stop.
- Recording remains pending locally on iPhone.
- When Mac app returns, it should detect and offer import into the relevant take when possible.

### iPhone Hits Hard Limits

iPhone may stop recording only for hard device constraints:

- storage full
- camera permission revoked
- app terminated
- thermal/system interruption
- unrecoverable AVFoundation error

The iPhone must preserve whatever media was captured and report the stop reason to the Mac.

## Synchronization Requirements

- Mac is authoritative for the Take Timeline.
- iPhone must prepare before the Mac starts the take when Remote iPhone Camera is enabled.
- Start should use a command/acknowledgement protocol with timestamps.
- Stop should use a command/acknowledgement protocol with timestamps.
- The transferred Master Camera Recording must include timing metadata sufficient for Mac-side alignment.
- v1 may correct offset through trimming/alignment metadata.
- Future work may add stronger clock synchronization if drift is measurable.

## Recording and File Handling

- iPhone records locally first.
- Mac receives the master after stop or reconnect.
- Mac stores the result as the take's camera media.
- Mac should not use the monitor preview as the final camera media.
- If transfer is interrupted, it must resume or retry without losing the source file on iPhone.
- Pending iPhone recordings must be visible and recoverable from the iPhone app.

## Acceptance Criteria

- A paired iPhone appears in BlitzRecorder's Camera picker.
- Selecting it shows live monitor preview in the Preview Stage camera layer.
- Starting a Mac recording starts iPhone-local recording and Mac capture sources as one take.
- Stopping from Mac stops iPhone recording and transfers the master camera file into the take.
- Final export uses the transferred iPhone camera file as the Camera source.
- Lens selection works on supported multi-lens iPhones.
- Unsupported controls are hidden or disabled with clear state.
- Preview disconnect does not stop the iPhone recording.
- Mac disconnect does not stop the iPhone recording.
- User can stop recording from iPhone if Mac is unavailable.
- Pending iPhone recordings can be transferred after reconnect.
- Local network transport works without requiring USB.
- Wired transport is attempted where available, but failure falls back to local network transport.

## Implementation Notes

Recommended Apple frameworks:

- SwiftUI for the iPhone companion UI.
- AVFoundation for iPhone camera capture and control.
- iOS 26 Cinematic video capture APIs where supported by the active device and format.
- VideoToolbox for low-latency monitor preview encoding.
- Network.framework for command/control, preview transport, discovery, and transfer.
- Bonjour for discovery.

The iPhone app should advertise capabilities, not assumptions. The Mac should render controls from the reported capability model.

## Open Questions

- Exact preview codec and transport framing.
- Exact file transfer protocol and resume strategy.
- Whether paired device trust should be iCloud-synced or local-only.
- Whether the first v1 includes manual IP/code pairing or reserves it for hard discovery failures.
- How to map orphan/pending iPhone recordings back to a Mac take when the Mac crashed before recording metadata was persisted.

## References

- Apple: Supporting Continuity Camera in your macOS app: https://developer.apple.com/documentation/AVFoundation/supporting-continuity-camera-in-your-macos-app
- Apple: AVCam camera app sample: https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app
- Apple: AVCamManual manual capture sample: https://developer.apple.com/library/archive/samplecode/AVCamManual/Introduction/Intro.html
- Apple: System video effects and microphone modes: https://developer.apple.com/documentation/avfoundation/system-video-effects-and-microphone-modes
- Apple: VideoToolbox low-latency encoding WWDC21: https://developer.apple.com/videos/play/wwdc2021/10158/
- Apple: Network.framework peer-to-peer guidance: https://developer.apple.com/forums/thread/776069
- Apple: Bonjour/local network privacy guidance: https://developer.apple.com/news/?id=0oi77447
