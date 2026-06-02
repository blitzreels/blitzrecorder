# Scene editor workspace

## Goal

Create a scene editing workspace for BlitzRecorder that feels like a focused creative tool, while keeping the everyday capture screen simple.

The design must preserve all existing recording, source, crop, canvas, audio, and scene features. This is a reorganization of the UI, not a feature reduction.

## Product model

BlitzRecorder has three distinct surfaces:

- Capture: simple setup and start recording.
- Edit Scenes: scene composition workspace.
- Live Recording: small menu bar or floating controller for elapsed time, scene switching, pause, stop, and source changes.

Edit Scenes is available only before recording. During recording it remains visible but disabled.

## Layout

The editor uses a three-column workspace:

```text
[ Scene Library ]  [ Editable Canvas ]  [ Inspector ]
```

### Scene library

The left column is for scene management, not source settings.

It should include:

- Scene list scoped to the current canvas format.
- Active scene state.
- Small scene thumbnails.
- Scene name.
- Scene type summary, such as `Screen + Camera`, `Screen Only`, or `Camera Only`.
- Add scene.
- Duplicate scene.
- Rename scene.
- Delete scene.
- Reorder scenes.
- Apply preset to current scene.

Recording rules:

- Scene switching is allowed during recording from the live controller.
- Scene editing is not allowed during recording.

### Editable canvas

The center column is the primary visual surface.

It should include:

- Existing `PreviewStageView` as the editing engine.
- Drag and resize for scene layers.
- Layer selection from canvas.
- Source selection sync with the inspector.
- Crop affordances on the selected asset.
- Safe-zone overlays.
- Canvas background preview.
- Canvas format locked for the take.

The canvas should be the main visual surface. Side panels should feel secondary.

Crop mode rules:

- Orange is reserved for crop/editing mode.
- `Crop` and `Done cropping` appear in the same place, just above the selected asset.
- The full crop source may extend outside the canvas, but never outside the center preview stage.
- Screen crop editing should show the raw screen source behind the currently selected visible crop zone.
- Camera crop editing should show the full camera source behind the currently selected crop zone.
- Non-relevant UI should be visually quiet while crop mode is active.

### Inspector

The right column is contextual and tabbed.

Recommended tabs:

- Scene
- Source
- Canvas

The inspector should show controls for the selected object, not every setting at once.

#### Scene tab

Includes:

- Layout preset selection.
- Source visibility.
- Layer order.
- Fit selected layer.
- Reset scene layout.
- Screen split height controls.
- Scene-level source composition settings.

#### Source tab

When screen is selected:

- Display, app, or window source picker.
- Full display mode.
- Active window fit mode.
- Manual crop mode.
- Active window refresh.
- Window zoom.
- Fit Window action.
- Reset crop.

When camera is selected:

- Camera picker.
- Local camera choices.
- iPhone camera choices.
- Transparent webcam toggle.
- Camera crop presets.
- Free crop.
- Center crop.
- Reset crop.

When microphone is selected:

- Microphone picker.
- Gain.
- Live levels.
- Mute or hide state.

When system audio is selected:

- System audio gain.
- Live levels.
- Mute or hide state.

#### Canvas tab

Includes:

- Canvas background style.
- Canvas padding.
- Rule of thirds.
- Social safe zones.
- Output format visibility, while still keeping actual canvas format locked for the take.

## Visual direction

The UI should feel closer to Figma, Final Cut, Screen Studio, or a refined OBS scene editor than a settings form.

Principles:

- Canvas is 120% visual priority.
- Scene library is 70% priority.
- Inspector is 60% priority.
- Use dense but calm controls.
- Avoid nested cards.
- Avoid equal visual weight across every control.
- Use icons for tools and compact commands.
- Keep visible explanatory text minimal.

Color roles:

- Mint: selected, ready, active.
- Orange: crop or temporary edit mode.
- Red: recording, stop, destructive.
- Neutral glass: inactive surfaces and secondary controls.

## Capture screen relationship

The capture screen should become simpler after this editor exists.

Capture should show:

- Read-only preview.
- Active scene switcher.
- Source readiness.
- Record button.
- Export/settings shortcut.

Capture should not show:

- Full scene preset editor.
- Full canvas appearance controls.
- Detailed crop controls.
- Advanced source layout controls.

Those move into Edit Scenes.

## Live Recording Relationship

During recording, the main window should not become an editor.

Live controls should live in a small menu-bar or floating controller:

- Recording time.
- Pause.
- Stop.
- Scene switcher.
- Switch window/app for screen source.

Changing the screen app/window during recording should be allowed, but should not update the saved scene by default.

## Implementation Notes

Recommended implementation order:

1. Add `EditScenesView`.
2. Extract existing sidebar controls into reusable components.
3. Move scene list into the left editor column.
4. Move `PreviewStageRepresentable(view: vm.previewStage)` into the center editor column.
5. Move source, scene, and canvas controls into right inspector tabs.
6. Wire `Edit scenes` to open this workspace.
7. Disable editor entry while recording.
8. Simplify Capture after parity is confirmed.

Do not rewrite `PreviewStageView` as SwiftUI. Keep the AppKit preview as the editing engine and wrap it in SwiftUI.

## Non-Goals For First Version

- Switching canvas format while recording.
- Editing scene library while recording.
- Keyframe animation editor.
- Multi-track timeline.
- Full OBS-style nested source graph.

## Acceptance Criteria

- All existing source, crop, canvas, scene, audio, and recording settings remain reachable.
- Selecting a layer on the canvas selects the matching source in the inspector.
- Selecting a source in the inspector selects the matching canvas layer.
- Crop controls are anchored to the selected asset.
- Screen crop editing shows the raw source outside the visible canvas when needed.
- The raw source never overlaps the scene library or inspector.
- Capture screen is simpler after the editor exists.
- Recording state disables editing without hiding the current scene context.
