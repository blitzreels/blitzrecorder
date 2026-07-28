# Changelog

Notable public releases will be documented here.

This project uses GitHub Releases for downloadable macOS builds. Release tags use the `vX.Y.Z` format.

## Unreleased

## 0.9.0 - 2026-07-28

- Improved recording start and stop reliability when the macOS screen picker is open or changing sources.
- Coalesced rapid screen-capture configuration changes to reduce redundant work and keep the latest settings.
- Made selected-window fitting reliable across supported macOS versions without requesting broader screen access.
- Prevented stale window-fit operations from resizing the wrong window after recording state changes.

## 0.7.0 - 2026-07-24

- Faster exports: new Metal-based export compositor with hardware video encoding when available.
- Added export performance presets and frame rate options in the editor export panel.
- Added optional background music when exporting a project.
- Screen picker can now retarget an active stream, and app/window capture geometry is more reliable.
- Transcripts can be copied as Markdown from the project library.

## 0.6.0 - 2026-07-23

- App capture now records the selected app's main window instead of combining all of its windows.
- Screen, camera, and audio preview resources now pause outside Record mode and stop when the studio window closes.
- Editor playback now follows the longest available media source, preventing short audio tracks from ending playback early.
- Reduced idle editor work by running the display refresh link only during playback.
- Refined the editor toolbar, added double-click window filling, and improved narrow preview status messages.

## 0.5.0 - 2026-07-21

- Fixed export framing so the exported video matches the editor preview, including camera and screen crop positions.
- Added an on-screen aspect ratio switch (9:16 / 16:9) above the canvas.
- Added a Fit or Fill control for the screen source in the editor, so you can show the whole recording or crop it to the frame.
- Added clear export confirmation with the saved file path and a Reveal in Finder button, plus a readable error if an export fails.
- Exports now save only the video file, without extra transcript files alongside it.
- Improved export reliability when saving to external or non-Apple-formatted drives.

## 0.4.1 - 2026-07-21

- Added in-app update checking through a signed, direct-download release feed.
- Fixed content-zoom keyboard shortcuts so they work across keyboard layouts.
- Fixed editor timeline track durations for captures with startup frames or shorter sources.
- Improved source-window zoom and fit behavior in the canvas.
- Refined transcript handling and project library interactions.

## 0.4.0 - 2026-07-16

- Added a Projects library with playback, multi-selection, rename, delete, Finder access, and export workflows.
- Added optional on-device transcription with speaker timelines, searchable transcripts, editable speaker details, and generated project titles.
- Expanded the editor with a visual filmstrip, clearer scene changes, source crop and zoom controls, canvas padding, screen corners, and shadows.
- Added export controls for format, resolution, quality, bitrate estimates, and destination placement.
- Improved recording settings, screen-source zoom, permission recovery, microphone startup, audio finalization, and capture error reporting.
- Refined iPhone companion pairing state and recording-library cleanup controls.

## 0.3.0 - 2026-07-15

- Redesigned the recording studio and editor around a shared native control system.
- Added synchronized full-timeline playback for screen, camera, microphone, and system audio.
- Improved recording startup, finalization, source selection, permission recovery, and error reporting.
- Fixed editor refresh, crop, frame-ratio, scene resizing, and export placement behavior.
- Added a sandbox-safe DMG packaging fallback for current macOS releases.
