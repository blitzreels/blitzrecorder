import AppKit
import SwiftUI

struct EditorExportControls: View {
    @Bindable var vm: RecorderViewModel
    let project: RecordingProject?
    @Binding var isPresented: Bool
    @Binding var destination: EditorExportDestination
    @Binding var additionalExportLayouts: Set<CaptureLayout>
    @Binding var selectedExportPreset: ExportPerformancePreset
    @Binding var selectedFormat: OutputVideoFormat
    @Binding var selectedResolution: OutputResolution
    @Binding var selectedExportFramesPerSecond: Int
    @Binding var selectedExportQuality: ExportVideoQuality
    @Binding var selectedExportPlaybackRate: ExportPlaybackRate
    let recipe: EditorExportRecipe
    let persist: (String) -> Void
    let export: () -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(
                vm.state == .finishing ? "Exporting" : "Export",
                systemImage: vm.state == .finishing ? "hourglass" : "square.and.arrow.up"
            )
        }
        .blitzButton(.accent)
        .controlSize(.large)
        .disabled(project == nil || vm.state != .idle)
        .help("Choose export settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popover
        }
    }

    private var popover: some View {
        EditorExportPopover(configuration: .init(
            destination: $destination,
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
                    guard $0 != recipe.profile.videoQuality.resolvedMenuQuality else { return }
                    useCustomProfile()
                    selectedExportQuality = $0
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
            estimatedSizeCaption: recipe.encoding.estimatedSizeCaption,
            encodingDetail: recipe.encoding.detail,
            directory: vm.settings.outputDirectory,
            canExport: project != nil && vm.state == .idle && !vm.isExportingVariants,
            export: export,
            chooseFolder: {
                isPresented = false
                vm.chooseOutputFolder { _ in isPresented = true }
            }
        ))
    }

    private func useCustomProfile() {
        selectedResolution = recipe.profile.resolution
        selectedExportFramesPerSecond = recipe.profile.framesPerSecond
        selectedExportQuality = recipe.profile.videoQuality
        selectedExportPreset = .custom
    }
}
