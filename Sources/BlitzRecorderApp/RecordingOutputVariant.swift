import Foundation

struct RecordingOutputVariant: Codable, Equatable, Identifiable {
    let layout: CaptureLayout
    var scenes: [RecordingProject.SceneEventSnapshot]
    var textOverlays: [RecordingProject.TextOverlaySnapshot]
    var id: CaptureLayout { layout }

    struct Request {
        let project: RecordingProject
        let layout: CaptureLayout
    }

    static func make(_ request: Request) -> Self {
        let scenes = TakeFileStore().sceneEvents(from: request.project).map { event in
            var scene = event.scene
            let video = scene.enabledSources.intersection([.screen, .camera])
            let preset: ScenePreset = video == [.screen] ? .screenFullscreen
                : video == [.camera] ? .webcamFullscreen : .defaultPreset(for: request.layout)
            scene.sceneLayout = SceneLayout.presetLayout(preset, for: request.layout,
                screenAspectRatio: scene.screenSourceGeometry.aspectRatio())
            scene.screenContentMode = .fit
            return RecordingProject.SceneEventSnapshot(.init(time: event.time, scene: scene, transition: event.transition))
        }
        return .init(layout: request.layout, scenes: scenes, textOverlays: request.project.timelineEdits.textOverlays)
    }
}

extension RecordingProject {
    var selectedOutputLayout: CaptureLayout {
        edits.activeOutputLayout ?? CaptureLayout(rawValue: settings.layout) ?? .horizontal
    }

    var outputProject: RecordingProject { outputProject(for: selectedOutputLayout) }

    func outputProject(for layout: CaptureLayout) -> RecordingProject {
        guard layout.rawValue != settings.layout else { return self }
        let variant = edits.outputVariants.first { $0.layout == layout }
            ?? RecordingOutputVariant.make(.init(project: self, layout: layout))
        var result = self
        result.settings.layout = layout.rawValue
        result.sceneEvents = variant.scenes
        var edits = edits
        edits.textOverlays = variant.textOverlays.map(\.overlay)
        result.timelineEdits = .init(edits)
        return result
    }
}

struct EditorVariantExportRequest {
    let export: EditorExportRequest
    let layouts: [CaptureLayout]
}

extension RecorderViewModel {
    var editorProject: RecordingProject? { lastExportedProject?.outputProject }

    func selectOutputLayout(_ layout: CaptureLayout) {
        guard let project = lastExportedProject else { return }
        var edits = project.edits
        if layout.rawValue == project.settings.layout {
            edits.activeOutputLayout = nil
        } else {
            if !edits.outputVariants.contains(where: { $0.layout == layout }) {
                edits.outputVariants.append(.make(.init(project: project, layout: layout)))
            }
            edits.activeOutputLayout = layout
        }
        _ = applyTimelineEdits(.init(edits: edits, actionName: "Change Output Format"))
    }

    @discardableResult
    func applyOutputTextEdits(_ request: EditorTimelineEditsChange) -> Bool {
        guard let project = lastExportedProject, let layout = project.edits.activeOutputLayout else {
            return applyTimelineEdits(request)
        }
        var edits = request.edits
        guard let index = edits.outputVariants.firstIndex(where: { $0.layout == layout }) else { return false }
        edits.outputVariants[index].textOverlays = edits.textOverlays.map(RecordingProject.TextOverlaySnapshot.init)
        edits.textOverlays = project.edits.textOverlays
        return applyTimelineEdits(.init(edits: edits, actionName: request.actionName))
    }

    struct OutputSceneChange {
        let index: Int
        let mutate: (inout RecordingScene) -> Void
    }

    func changeOutputScene(_ request: OutputSceneChange) -> Bool {
        guard let project = lastExportedProject, let layout = project.edits.activeOutputLayout else { return false }
        var edits = project.edits
        guard let index = edits.outputVariants.firstIndex(where: { $0.layout == layout }),
              edits.outputVariants[index].scenes.indices.contains(request.index) else { return false }
        let snapshot = edits.outputVariants[index].scenes[request.index]
        guard var scene = RecordingScene(snapshot: snapshot.scene) else { return false }
        request.mutate(&scene)
        edits.outputVariants[index].scenes[request.index] = .init(.init(time: snapshot.time, scene: scene,
            transition: RecordingSceneTransition(duration: snapshot.transition.duration, curve: snapshot.transition.curve == "linear" ? .linear : .easeInOut)))
        return applyTimelineEdits(.init(edits: edits, actionName: "Edit Output Framing"))
    }

    struct OutputSplit {
        let time: Double
        let duration: Double
    }

    func splitOutputScene(_ request: OutputSplit) -> Bool {
        guard let project = lastExportedProject, let layout = project.edits.activeOutputLayout,
              request.time > 0.05, request.time < request.duration - 0.05 else { return false }
        var edits = project.edits
        guard let index = edits.outputVariants.firstIndex(where: { $0.layout == layout }) else { return false }
        var scenes = edits.outputVariants[index].scenes
        guard !scenes.contains(where: { abs($0.time - request.time) < 0.01 }),
              let previous = scenes.last(where: { $0.time <= request.time }),
              let scene = RecordingScene(snapshot: previous.scene) else { return false }
        scenes.append(.init(.init(time: request.time, scene: scene)))
        edits.outputVariants[index].scenes = scenes.sorted { $0.time < $1.time }
        return applyTimelineEdits(.init(edits: edits, actionName: "Split Segment"))
    }

    func joinOutputScene(_ eventIndex: Int) -> Bool {
        guard let project = lastExportedProject, let layout = project.edits.activeOutputLayout else { return false }
        var edits = project.edits
        guard let index = edits.outputVariants.firstIndex(where: { $0.layout == layout }), eventIndex > 0,
              edits.outputVariants[index].scenes.indices.contains(eventIndex) else { return false }
        edits.outputVariants[index].scenes.remove(at: eventIndex)
        return applyTimelineEdits(.init(edits: edits, actionName: "Join Segment"))
    }
}
