import BlitzRecorderCore
import BlitzRecorderDesign
import SwiftUI

/// Everything the camera tab shows, derived once from the store so each state can be previewed.
struct CompanionCameraPresentation: Equatable {
    struct Pairing: Equatable {
        let code: String
        let connection: RemoteCameraConnectionState
        let step: CompanionPairingStep
        /// The Mac asking to connect, once it has said hello. Older Mac apps do not send a name.
        let macName: String?
    }

    enum Stage: Equatable {
        case pairing(Pairing)
        case ready
        case preparing
        case recording(elapsed: String)
        case stopping
        case sending(fraction: Double?)
        case saved
        case failed(message: String)
    }

    let isMacConnected: Bool
    let stage: Stage
    let macName: String?
    let captureFacts: String?
    let warning: String?
    let waitingClipCount: Int

    var isPairing: Bool {
        if case .pairing = stage { return true }
        return false
    }

    var isRecording: Bool {
        switch stage {
        case .preparing, .recording, .stopping: true
        default: false
        }
    }
}

struct CompanionCameraActions {
    let approveMac: () -> Void
    let useCode: () -> Void
    let declineMac: () -> Void
    let findMac: () -> Void
    let showDetails: () -> Void
    let stop: () -> Void
    let openClips: () -> Void
}

struct CompanionCameraOverlay: View {
    let presentation: CompanionCameraPresentation
    let actions: CompanionCameraActions
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !presentation.isPairing {
                    statusBar
                }
                Spacer(minLength: 8)
                Button(action: actions.showDetails) {
                    Image(systemName: "info.circle")
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Connection details")
            }
            Spacer(minLength: 16)
            bottomContent
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, alignment: isLandscape ? .trailing : .center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.easeOut(duration: 0.15), value: presentation)
    }

    private var statusBar: some View {
        Group {
            switch presentation.stage {
            case .recording(let elapsed):
                CompanionStatusLabel(text: "REC  \(elapsed)", tone: .recording)
                    .font(BlitzType.numeric)
            case .preparing:
                CompanionStatusLabel(text: "Starting", tone: .recording)
            default:
                if presentation.isMacConnected {
                    CompanionStatusLabel(text: presentation.macName ?? "Connected", tone: .live)
                } else {
                    CompanionStatusLabel(text: "Mac not connected", tone: .warning)
                }
            }
        }
        .font(BlitzType.label)
        .foregroundStyle(BlitzUI.primaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: BlitzControlMetrics.height(.regular))
        .blitzGlass(cornerRadius: BlitzUI.cardRadius)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bottomContent: some View {
        switch presentation.stage {
        case .pairing(let pairing):
            CompanionPairingCard(pairing: pairing, actions: actions)
        case .recording:
            recordingControls
        default:
            statusCard
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            if let warning = presentation.warning {
                warningLine(warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blitzGlass(cornerRadius: BlitzUI.surfaceRadius)
            }
            Button(action: actions.stop) {
                Label("Stop recording", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.record)
            .controlSize(.extraLarge)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if case .failed = presentation.stage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BlitzUI.warning)
                        .accessibilityHidden(true)
                }
                Text(cardTitle)
                    .font(BlitzType.title)
                    .foregroundStyle(BlitzUI.primaryText)
                Spacer(minLength: 8)
                if case .sending(let fraction) = presentation.stage, let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(BlitzType.numeric)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            switch presentation.stage {
            case .sending(let fraction):
                ProgressView(value: fraction ?? 0)
                    .tint(BlitzUI.accent)
            case .preparing, .stopping:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            default:
                EmptyView()
            }
            if let detail = cardDetail {
                Text(detail)
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = presentation.warning {
                warningLine(warning)
            }
            cardActions
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlass(cornerRadius: BlitzUI.surfaceRadius)
    }

    @ViewBuilder
    private var cardActions: some View {
        switch presentation.stage {
        case .failed:
            Button("See details", action: actions.showDetails)
                .blitzButton(.secondary)
        case .saved:
            Button("Open Clips", systemImage: BlitzSymbols.library, action: actions.openClips)
                .blitzButton(.secondary)
        case .ready where presentation.waitingClipCount > 0:
            Button(Self.waitingTitle(presentation.waitingClipCount), systemImage: BlitzSymbols.library,
                   action: actions.openClips)
                .blitzButton(.secondary)
        default:
            EmptyView()
        }
    }

    private func warningLine(_ warning: String) -> some View {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
            .font(BlitzType.label)
            .foregroundStyle(BlitzUI.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cardTitle: String {
        switch presentation.stage {
        case .ready: "Ready to record"
        case .preparing: "Getting ready"
        case .stopping: "Finishing the clip"
        case .sending: "Sending to your Mac"
        case .saved: "Saved on this iPhone"
        case .failed: "Recording stopped"
        case .pairing, .recording: ""
        }
    }

    private var cardDetail: String? {
        switch presentation.stage {
        case .ready:
            presentation.captureFacts ?? "Your Mac starts and stops each take."
        case .sending:
            "Keep BlitzRecorder open on both devices."
        case .saved:
            "Your Mac imports it the next time it connects."
        case .failed(let message):
            message
        default:
            presentation.captureFacts
        }
    }

    static func waitingTitle(_ count: Int) -> String {
        count == 1 ? "1 clip waiting to send" : "\(count) clips waiting to send"
    }

}

private struct CompanionPairingCard: View {
    let pairing: CompanionCameraPresentation.Pairing
    let actions: CompanionCameraActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                BlitzAppIcon(image: Bundle.main.blitzRecorderMacIcon.map(Image.init(uiImage:)), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BlitzType.title)
                        .foregroundStyle(BlitzUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch pairing.step {
            case .waitingForMac:
                HStack(spacing: 10) {
                    if Self.needsRetry(pairing.connection) {
                        Button("Try again", systemImage: "arrow.clockwise", action: actions.findMac)
                            .blitzButton(.secondary)
                    }
                    Spacer(minLength: 8)
                    Link("No Mac app yet?", destination: BlitzRecorderProductIdentity.macInstallURL)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.accent)
                }
            case .approval:
                Button(action: actions.approveMac) {
                    Label("Connect", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .controlSize(.extraLarge)
                HStack(spacing: 10) {
                    Button("Use a code instead", action: actions.useCode)
                        .blitzButton(.quiet)
                    Spacer(minLength: 0)
                    Button("Not now", action: actions.declineMac)
                        .blitzButton(.quiet)
                }
            case .updateNeeded(let macIsOlder):
                HStack(spacing: 10) {
                    Button("Try again", systemImage: "arrow.clockwise", action: actions.findMac)
                        .blitzButton(.secondary)
                    Spacer(minLength: 8)
                    if macIsOlder {
                        Link("Get the latest Mac app", destination: BlitzRecorderProductIdentity.macInstallURL)
                            .font(BlitzType.label)
                            .foregroundStyle(BlitzUI.accent)
                    }
                }
            case .code:
                VStack(alignment: .leading, spacing: 4) {
                    Text(pairing.code)
                        .font(BlitzType.largeTitle.monospacedDigit())
                        .tracking(6)
                        .foregroundStyle(BlitzUI.primaryText)
                        .textSelection(.enabled)
                        .accessibilityLabel("Pairing code \(pairing.code.map(String.init).joined(separator: " "))")
                    Text("Type it on your Mac when it asks.")
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
        }
        .padding(20)
        .blitzGlass(cornerRadius: BlitzUI.surfaceRadius)
    }

    private var title: String {
        switch pairing.step {
        case .waitingForMac: "Open BlitzRecorder on your Mac"
        case .approval: pairing.macName.map { "Connect to \($0)?" } ?? "Connect to your Mac?"
        case .code: "Enter this code on your Mac"
        case .updateNeeded(let macIsOlder): macIsOlder ? "Update BlitzRecorder on your Mac" : "Update this app"
        }
    }

    private var subtitle: String {
        switch pairing.step {
        case .waitingForMac: Self.needsRetry(pairing.connection)
            ? "Can’t reach your Mac. Check that both are on the same Wi‑Fi, then try again."
            : "Choose this iPhone as the camera. Same Wi‑Fi on both."
        case .approval: "BlitzRecorder on this Mac wants to use your iPhone as its camera. It is remembered for next time."
        case .code: "Only needed once. After that, your Mac connects on its own."
        case .updateNeeded(let macIsOlder): macIsOlder
            ? "This iPhone app is newer than BlitzRecorder on your Mac. Update the Mac app, then try again."
            : "BlitzRecorder on your Mac is newer than this app. Update BlitzRecorder Camera from the App Store."
        }
    }

    private static func needsRetry(_ connection: RemoteCameraConnectionState) -> Bool {
        switch connection {
        case .degraded, .disconnected, .unavailable: true
        case .discovering, .pairing, .connected: false
        }
    }
}

#Preview("Pairing") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .pairing(.init(code: "482913", connection: .pairing, step: .approval, macName: "Virgile’s MacBook Pro")), macName: nil,
        captureFacts: nil, warning: nil, waitingClipCount: 0
    ))
}

#Preview("Waiting") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .pairing(.init(code: "482913", connection: .discovering, step: .waitingForMac, macName: nil)), macName: nil,
        captureFacts: nil, warning: nil, waitingClipCount: 0
    ))
}

#Preview("Ready") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .ready, macName: "Virgile’s MacBook Pro",
        captureFacts: "Wide · 4K · 30 fps", warning: nil, waitingClipCount: 2
    ))
}

#Preview("Recording") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .recording(elapsed: "12:31"), macName: "Virgile’s MacBook Pro",
        captureFacts: "Wide · 4K · 30 fps", warning: "iPhone camera lens looks smudged; wipe it clean", waitingClipCount: 0
    ))
}

#Preview("Sending") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .sending(fraction: 0.42), macName: "Virgile’s MacBook Pro",
        captureFacts: nil, warning: nil, waitingClipCount: 0
    ))
}

#Preview("Failed") {
    CompanionCameraPreviewHost(presentation: .init(
        isMacConnected: true, stage: .failed(message: "The Mac disconnected during the take. The clip is saved on this iPhone."),
        macName: "Virgile’s MacBook Pro", captureFacts: nil, warning: nil, waitingClipCount: 0
    ))
}

private struct CompanionCameraPreviewHost: View {
    let presentation: CompanionCameraPresentation

    var body: some View {
        CompanionCameraOverlay(presentation: presentation, actions: .init(
            approveMac: {}, useCode: {}, declineMac: {}, findMac: {}, showDetails: {}, stop: {}, openClips: {}
        ))
        .background {
            LinearGradient(colors: [.indigo, .brown, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}
