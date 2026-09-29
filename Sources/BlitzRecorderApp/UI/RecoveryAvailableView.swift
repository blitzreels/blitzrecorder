import AppKit
import SwiftUI

struct RecoveryAvailableView: View {
    @Bindable var vm: RecorderViewModel
    let recovery: RecordingRecoveryOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.glyph(12))
                    .foregroundStyle(BlitzUI.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording needs recovery")
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.warning)
                    Text(recovery.reason)
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.supportingText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recovery.takeDirectory.path)
                        .font(BlitzType.footnote.monospaced())
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(recovery.takeDirectory.path)
                }

                Spacer(minLength: 8)
            }

            Divider()
                .background(BlitzUI.hoverFill)

            ViewThatFits(in: .horizontal) {
                recoveryActionRow
                VStack(alignment: .leading, spacing: 8) {
                    recoveryPrimaryActionRow
                    recoverySecondaryActionRow
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private var recoveryActionRow: some View {
        HStack(spacing: 8) {
            recoveryPrimaryActions
            recoverySecondaryActions
        }
    }

    private var recoveryPrimaryActionRow: some View {
        HStack(spacing: 8) {
            recoveryPrimaryActions
        }
    }

    private var recoverySecondaryActionRow: some View {
        HStack(spacing: 8) {
            recoverySecondaryActions
        }
    }

    @ViewBuilder
    private var recoveryPrimaryActions: some View {
        if recovery.canRetryExport {
            DockActionButton(title: "Retry Export", systemImage: "arrow.clockwise", help: "Try exporting the recovered source files again") {
                vm.retryRecoveredExport()
            }
        }

        DockActionButton(title: "Reveal Files", systemImage: "tray.full", help: recovery.takeDirectory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([recovery.takeDirectory])
        }
    }

    @ViewBuilder
    private var recoverySecondaryActions: some View {
        DockActionButton(title: "Export Settings", systemImage: "slider.horizontal.3") {
            vm.onPresentSettings?(.recording)
        }

        DockActionButton(title: "Dismiss", systemImage: "xmark") {
            vm.clearPostRecordingStatus()
        }
    }
}
