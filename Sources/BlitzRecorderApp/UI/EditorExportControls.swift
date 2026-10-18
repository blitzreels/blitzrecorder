import AppKit
import SwiftUI

struct EditorExportControls: View {
    @Bindable var vm: RecorderViewModel
    let project: RecordingProject?
    @Binding var additionalExportLayouts: Set<CaptureLayout>
    @Binding var selectedExportPreset: ExportPerformancePreset
    @Binding var selectedFormat: OutputVideoFormat
    @Binding var selectedResolution: OutputResolution
    @Binding var selectedExportFramesPerSecond: Int
    @Binding var selectedExportQuality: ExportVideoQuality
    @Binding var selectedExportPlaybackRate: ExportPlaybackRate
    @Binding var selectedExportTargetSize: Int64?
    let recipe: EditorExportRecipe
    let sizeEstimate: (ExportVideoQuality) -> String
    let persist: (String) -> Void
    let export: () -> Void
    let section: EditorExportSettings.Section

    var body: some View {
        EditorExportSettings(configuration: .init(
            additionalLayouts: $additionalExportLayouts,
            currentLayout: vm.lastExportedProject?.selectedOutputLayout ?? .horizontal,
            format: Binding(
                get: { recipe.profile.videoQuality.resolvedOutputFormat(selectedFormat) },
                set: {
                    selectedFormat = recipe.profile.videoQuality.resolvedOutputFormat($0)
                    persist("Change Export Format")
                }
            ),
            resolution: Binding(
                get: { recipe.profile.resolution },
                set: {
                    guard $0 != recipe.profile.resolution else { return }
                    useCustomProfile()
                    selectedResolution = $0
                    persist("Change Export Resolution")
                }
            ),
            framesPerSecond: Binding(
                get: { recipe.profile.framesPerSecond },
                set: {
                    guard $0 != recipe.profile.framesPerSecond else { return }
                    useCustomProfile()
                    selectedExportFramesPerSecond = $0
                    persist("Change Export Frame Rate")
                }
            ),
            quality: Binding(
                get: { recipe.profile.videoQuality.resolvedMenuQuality },
                set: {
                    guard $0 != recipe.profile.videoQuality.resolvedMenuQuality || selectedExportTargetSize != nil
                    else { return }
                    useCustomProfile()
                    selectedExportQuality = $0
                    selectedExportTargetSize = nil
                    selectedFormat = $0.resolvedOutputFormat(selectedFormat)
                    persist("Change Export Quality")
                }
            ),
            playbackRate: Binding(
                get: { selectedExportPlaybackRate },
                set: {
                    guard selectedExportPlaybackRate != $0 else { return }
                    selectedExportPlaybackRate = $0
                    persist("Change Export Speed")
                }
            ),
            estimatedSize: recipe.estimatedSize,
            fileSize: .init(
                bytes: recipe.estimatedFileBytes,
                range: recipe.fileSizeRange,
                isCustom: selectedExportTargetSize != nil,
                isAvailable: !recipe.profile.videoQuality.requiresQuickTime,
                perVideo: (additionalExportLayouts.count + 1) > 1,
                warning: recipe.sizeWarning,
                select: {
                    guard selectedExportTargetSize != $0 else { return }
                    selectedExportTargetSize = $0
                    persist($0 == nil ? "Reset Export Size" : "Change Export Size")
                }
            ),
            sizeEstimate: sizeEstimate,
            encodingDetail: recipe.encoding.detail,
            directory: vm.settings.outputDirectory,
            canExport: project != nil && vm.state == .idle && !vm.isExporting,
            export: export,
            chooseFolder: vm.chooseOutputFolder
        ), section: section)
    }

    private func useCustomProfile() {
        selectedResolution = recipe.profile.resolution
        selectedExportFramesPerSecond = recipe.profile.framesPerSecond
        selectedExportQuality = recipe.profile.videoQuality
        selectedExportPreset = .custom
    }
}
