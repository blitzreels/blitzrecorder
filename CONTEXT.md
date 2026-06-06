# BlitzRecorder Context

BlitzRecorder is a recording studio for composing and capturing screen, camera, and audio into creator-ready takes.

## Language

**Scene**:
A named, switchable composition snapshot used while preparing or recording a take. A scene belongs to one canvas format and defines which visual sources are visible, which source bindings and framing choices apply, and how the sources are arranged on the canvas.
_Avoid_: Layout, preset, template

**Scene Library**:
The persistent set of user-manageable scenes available for recording. The scene library is app-level, survives app launches, and is organized by canvas format.
_Avoid_: Take scenes, preset list

**Scene Management Editor**:
The place where users create, duplicate, rename, delete, reorder, and reset scenes. Scene presets live in the scene management editor rather than in the primary scene-switching list.
_Avoid_: Preset grid

**Edit Scenes Mode**:
A pre-recording mode for managing and editing scenes. Edit scenes mode is unavailable while recording; during recording, users switch scenes but do not edit the scene library.
_Avoid_: Studio mode

**Default Scene**:
A starter scene included in a new scene library. BlitzRecorder starts each canvas format with practical screen and camera scenes such as Screen + Cam, Screen Only, Cam Only, and a camera-overlay or side-by-side scene.
_Avoid_: Preset

**Current Scene**:
The selected scene in the scene library for the active canvas format. Each canvas format remembers its own current scene, and edits to composition, source visibility, source bindings, and visual framing update that current scene automatically.
_Avoid_: Unsaved scene, working copy

**Live Scene**:
The current scene shown on the canvas and used for recording output. In v1, BlitzRecorder does not separate preview scenes from live scenes.
_Avoid_: Program scene, preview scene

**Scene Preset**:
A reusable starting template for creating or resetting a scene. A scene preset is not itself a scene and is not part of the primary scene-switching list.
_Avoid_: Scene, layout

**Canvas Format**:
The output aspect shape of the recording canvas, such as vertical short-form video or horizontal YouTube video. Canvas format is fixed for a take and is not changed while recording.
_Avoid_: Layout

**Source Binding**:
The default concrete input behind a source in a scene, such as a display, picked window, picked app, camera, or microphone. Screen source bindings can be overridden during a take; camera and audio source bindings are fixed for the take.
_Avoid_: Device setting

**Live Screen Target**:
The screen app, window, display, or picked content currently captured by the live scene during a take. Changing the live screen target updates the recording timeline but does not update the scene library unless the user explicitly saves it as the scene default.
_Avoid_: Scene, source binding

**Scene Slot**:
The area of a scene reserved for a visual source, independent from the concrete source binding currently shown there. A scene slot stays stable when a source binding changes.
_Avoid_: Source frame

**Source Framing**:
The fit, crop, pan, or zoom used to place a concrete source binding inside a scene slot. Source framing is automatic by default and can be overridden for a specific scene and source binding.
_Avoid_: Scene layout

**Scene Switch**:
Selecting a different scene while preparing or recording a take. A scene switch changes the canvas to the selected scene.
_Avoid_: Preset change

**Scene Update**:
A change to the current scene's content, source binding, source framing, or composition while the same scene remains selected.
_Avoid_: Scene switch
