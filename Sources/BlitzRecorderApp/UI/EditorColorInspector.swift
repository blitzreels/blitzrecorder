import AVFoundation
import SwiftUI

struct EditorColorInspector: View {
    @Bindable var vm: RecorderViewModel
    let playback: EditorPlaybackController
    let project: RecordingProject?

    @State private var selectedRole: String?
    @State private var sourceImage: CGImage?

    private var sourcePath: String? {
        project?.sources.first(where: { $0.role == role })?.path
    }

    private var roles: [String] { playback.gradableCameraRoles }
    private var role: String? {
        selectedRole.flatMap { roles.contains($0) ? $0 : nil } ?? roles.first
    }
    private var savedGrade: CameraColorGrade { role.flatMap { playback.edits.cameraGrades[$0] } ?? .neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if roles.count > 1 { cameraRows }
            if let role {
                CameraGradeControls(configuration: .init(
                    savedGrade: savedGrade,
                    source: sourceImage,
                    resetTitle: "Reset \(title(for: role).lowercased())",
                    onPreview: { playback.previewCameraGrade(role: role, grade: $0) },
                    onCommit: { commit(.init(role: role, grade: $0)) }
                ))
                .id(role)
            } else {
                Text("This project has no camera to grade.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: sourcePath) { await loadPreview() }
        .onAppear { playback.setCameraGrading(true) }
        .onChange(of: role) { oldRole, _ in
            if let oldRole {
                playback.previewCameraGrade(role: oldRole, grade: playback.edits.cameraGrades[oldRole] ?? .neutral)
            }
        }
        .onDisappear {
            if let role { playback.previewCameraGrade(role: role, grade: savedGrade) }
            playback.setCameraGrading(false)
        }
    }

    private var cameraRows: some View {
        BlitzDropdown(configuration: .init(
            title: "Camera",
            selection: Binding(get: { role ?? "" }, set: { selectedRole = $0 }),
            options: roles.map { .init(value: $0, title: title(for: $0), detail: nil) }
        ))
    }

    private func loadPreview() async {
        sourceImage = nil
        guard let sourcePath else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: sourcePath)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let duration = (try? await generator.asset.load(.duration).seconds) ?? 0
        let time = CMTime(seconds: duration.isFinite ? duration / 4 : 0, preferredTimescale: 600)
        let image = try? await generator.image(at: time).image
        guard !Task.isCancelled else { return }
        sourceImage = image
    }

    private struct GradeChange {
        let role: String
        let grade: CameraColorGrade
    }

    private func commit(_ change: GradeChange) -> Bool {
        var edits = playback.edits
        edits.cameraGrades[change.role] = change.grade.isNeutral ? nil : change.grade
        guard edits != playback.edits else { return true }
        return vm.applyTimelineEdits(.init(edits: edits, actionName: "Change Color"))
    }

    private func title(for role: String) -> String {
        if let title = project?.cameraAngles.record(role: role)?.title, !title.isEmpty { return title }
        if roles.count == 1 { return "Camera" }
        return CameraFeeds.angleNumber(role: role).map { "Camera \($0)" } ?? "Camera"
    }
}
