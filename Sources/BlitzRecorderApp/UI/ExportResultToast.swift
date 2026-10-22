import AppKit
import SwiftUI

struct ExportResultToast: View {
    @Bindable var vm: RecorderViewModel
    @State private var isHovering = false

    private static let successLifetime: Duration = .seconds(6)

    private var isVisible: Bool {
        !vm.isExporting && !vm.isEditorVisible
            && (vm.exports.lastExportSucceededURL != nil || vm.exports.lastExportError != nil)
    }

    private var dismissTaskID: String {
        "\(vm.exports.lastExportSucceededURL?.path ?? "")|\(vm.exports.lastExportError ?? "")|\(isHovering)|\(isVisible)"
    }

    var body: some View {
        ZStack {
            if isVisible {
                content
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: isVisible)
        .task(id: dismissTaskID) {
            guard isVisible, vm.exports.lastExportError == nil, !isHovering else { return }
            try? await Task.sleep(for: Self.successLifetime)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.exports.lastExportError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(BlitzType.symbol(14))
                .foregroundStyle(vm.exports.lastExportError == nil ? BlitzUI.accent : BlitzUI.warning)
            Text(vm.exports.lastExportError.map { "Export failed: " + $0 } ?? savedTitle)
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .leading)
            if let url = vm.exports.lastExportSucceededURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(vm.exports.variantExportURLs.count > 1 ? vm.exports.variantExportURLs : [url])
                }
                .blitzButton(.secondary)
                .help(url.path)
            }
            Button(action: dismiss) { Image(systemName: "xmark") }
                .blitzButton(.quiet)
                .accessibilityLabel("Dismiss export status")
        }
        .controlSize(.small)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: BlitzUI.deepShadow, radius: 18, y: 6)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }

    private var savedTitle: String {
        vm.exports.variantExportURLs.count > 1
            ? "Saved \(vm.exports.variantExportURLs.count) videos"
            : "Saved \(vm.exports.lastExportSucceededURL?.lastPathComponent ?? "video")"
    }

    private func dismiss() {
        vm.exports.lastExportSucceededURL = nil
        vm.exports.lastExportError = nil
        vm.exports.variantExportURLs = []
    }
}
