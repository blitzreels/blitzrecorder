import AppKit
import SwiftUI

struct EditorExportControls: View {
    @Bindable var vm: RecorderViewModel
    let project: RecordingProject?
    @Binding var isPresented: Bool
    @Binding var inspectorTab: EditorInspectorTab
    @Binding var exportLayouts: Set<CaptureLayout>
    @Binding var selectedExportPreset: ExportPerformancePreset
    @Binding var selectedFormat: OutputVideoFormat
    @Binding var selectedResolution: OutputResolution
    @Binding var selectedExportFramesPerSecond: Int
    @Binding var selectedExportQuality: ExportVideoQuality
    @Binding var backgroundMusic: ExportBackgroundMusic?
    @Binding var backgroundMusicBookmarkData: Data?
    let recipe: EditorExportRecipe
    let persist: (String) -> Void
    let applyPreset: (EditorExportPresetRequest) -> Void
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
            layouts: $exportLayouts,
            currentLayout: vm.lastExportedProject?.selectedOutputLayout ?? .horizontal,
            preset: Binding(
                get: { selectedExportPreset },
                set: { preset in
                    guard let project else { return }
                    applyPreset(EditorExportPresetRequest(preset: preset, project: project))
                    persist("Change Export Preset")
                }
            ),
            format: Binding(
                get: { recipe.profile.videoQuality.resolvedOutputFormat(selectedFormat) },
                set: {
                    selectedFormat = recipe.profile.videoQuality.resolvedOutputFormat($0)
                    persist("Change Export Format")
                }
            ),
            resolution: Binding(
                get: { selectedResolution },
                set: {
                    selectedResolution = $0
                    selectedExportPreset = .custom
                    persist("Change Export Resolution")
                }
            ),
            framesPerSecond: Binding(
                get: { selectedExportFramesPerSecond },
                set: {
                    selectedExportFramesPerSecond = $0
                    selectedExportPreset = .custom
                    persist("Change Export Frame Rate")
                }
            ),
            quality: Binding(
                get: { selectedExportQuality.resolvedMenuQuality },
                set: {
                    selectedExportQuality = $0
                    selectedFormat = $0.resolvedOutputFormat(selectedFormat)
                    selectedExportPreset = .custom
                    persist("Change Export Quality")
                }
            ),
            summary: recipe.summary,
            estimatedSize: recipe.estimatedSize,
            estimatedSizeCaption: recipe.encoding.estimatedSizeCaption,
            encodingDetail: recipe.encoding.detail,
            directory: vm.settings.outputDirectory,
            musicSummary: backgroundMusic.map {
                "\($0.url.lastPathComponent) · \(EditorBackgroundMusicControl.volumeLabel(for: $0))"
            },
            musicControls: {
                EditorBackgroundMusicControl(
                    backgroundMusic: $backgroundMusic,
                    backgroundMusicBookmarkData: $backgroundMusicBookmarkData,
                    persist: persist
                )
            },
            canExport: project != nil && vm.state == .idle && !vm.isExportingVariants,
            export: export,
            showFolder: { NSWorkspace.shared.open(vm.settings.outputDirectory) },
            showBlitzReels: {
                isPresented = false
                inspectorTab = .blitzReels
            }
        ))
    }
}
