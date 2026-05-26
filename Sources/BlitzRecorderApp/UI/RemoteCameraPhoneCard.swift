import BlitzRecorderCore
import SwiftUI

struct RemoteCameraPhoneCard: View {
    @Bindable var vm: RecorderViewModel
    var compact = false

    private let mint = Color(red: 0.09, green: 1.0, blue: 0.65)

    var body: some View {
        VStack(spacing: 10) {
            phoneFrame

            if let progress = telemetry?.transferProgress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(mint)
            }
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 10 : 12)
        .blitzGlassSurface(cornerRadius: 14)
    }

    private var phoneFrame: some View {
        VStack(spacing: 0) {
            phoneStatusBar

            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deviceName)
                            .font(.system(size: compact ? 13 : 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(statusText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    phaseBadge
                }

                HStack(spacing: 7) {
                    metricChip(title: "Preview", value: previewLabel)
                    metricChip(title: "Transfer", value: transferLabel)
                }

                if !compact {
                    HStack(spacing: 7) {
                        metricChip(title: "Battery", value: batteryLabel)
                        metricChip(title: "Storage", value: storageLabel)
                    }
                }
            }
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.top, 8)
            .padding(.bottom, compact ? 12 : 14)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.025, blue: 0.03),
                    Color(red: 0.07, green: 0.08, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: .rect(cornerRadius: compact ? 22 : 26)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 22 : 26, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var phoneStatusBar: some View {
        HStack(spacing: 8) {
            Text("9:41")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 0)

            Image(systemName: previewHealthy ? "wifi" : "wifi.exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(previewHealthy ? .white.opacity(0.72) : .yellow.opacity(0.9))

            Image(systemName: batterySymbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(batteryColor)
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.top, compact ? 10 : 12)
        .padding(.bottom, 2)
    }

    private var phaseBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)
            Text(phaseLabel)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.10), in: .capsule)
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 9))
    }

    private var telemetry: RemoteCameraTelemetry? {
        vm.selectedRemoteCameraTelemetry
    }

    private var capabilities: RemoteCameraCapabilities? {
        vm.selectedRemoteCameraCapabilities
    }

    private var deviceName: String {
        vm.selectedRemoteCameraName ?? capabilities?.deviceName ?? "Remote iPhone"
    }

    private var statusText: String {
        if let telemetry {
            if telemetry.phase == .transferring, let progress = telemetry.transferProgress {
                return "Transfer \(Int((progress.fraction * 100).rounded()))%"
            }
            if let previewHealth = telemetry.previewHealth,
               previewHealth.framesSent > 0,
               !previewHealth.isHealthy {
                if let lastFrameAgeSeconds = previewHealth.lastFrameAgeSeconds,
                   lastFrameAgeSeconds >= 2 {
                    return "Waiting for live view"
                }
                return "iPhone connected"
            }
            return vm.selectedRemoteCameraStatus ?? "\(telemetry.phase.rawValue) - \(Int(telemetry.elapsedSeconds))s"
        }
        return vm.selectedRemoteCameraStatus ?? "Waiting for iPhone video"
    }

    private var statusColor: Color {
        if telemetry?.phase == .failed { return .red.opacity(0.9) }
        if previewHealthy { return mint }
        return .yellow.opacity(0.9)
    }

    private var phaseLabel: String {
        guard let phase = telemetry?.phase else { return "LINKED" }
        switch phase {
        case .idle:
            return "READY"
        case .preparing:
            return "PREP"
        case .recording:
            return "REC"
        case .stopping:
            return "STOP"
        case .transferring:
            return "SEND"
        case .pendingImport:
            return "IMPORT"
        case .failed:
            return "ERROR"
        }
    }

    private var phaseColor: Color {
        switch telemetry?.phase {
        case .recording:
            return .red.opacity(0.95)
        case .transferring, .preparing, .stopping:
            return .yellow.opacity(0.9)
        case .failed:
            return .red.opacity(0.95)
        case .idle, .pendingImport, nil:
            return mint
        }
    }

    private var batteryLabel: String {
        guard let battery = telemetry?.batteryLevel, battery >= 0 else { return "--" }
        return "\(Int((battery * 100).rounded()))%"
    }

    private var batterySymbol: String {
        guard let battery = telemetry?.batteryLevel, battery >= 0 else { return "battery.50" }
        if battery > 0.75 { return "battery.100" }
        if battery > 0.35 { return "battery.50" }
        return "battery.25"
    }

    private var batteryColor: Color {
        guard let battery = telemetry?.batteryLevel, battery >= 0 else { return .white.opacity(0.72) }
        return battery > 0.2 ? .white.opacity(0.72) : .yellow.opacity(0.9)
    }

    private var storageLabel: String {
        guard let bytes = telemetry?.storageFreeBytes, bytes > 0 else { return "--" }
        let gb = Double(bytes) / 1_000_000_000
        return "\(Int(gb.rounded())) GB"
    }

    private var previewLabel: String {
        guard let health = telemetry?.previewHealth, health.framesSent > 0 else { return "Waiting" }
        if let lastFrameAgeSeconds = health.lastFrameAgeSeconds, lastFrameAgeSeconds >= 2 {
            return "Stale"
        }
        return health.isHealthy ? "Live" : "\(Int((health.droppedFrameRatio * 100).rounded()))% drop"
    }

    private var transferLabel: String {
        guard let progress = telemetry?.transferProgress else { return "Idle" }
        return "\(Int((progress.fraction * 100).rounded()))%"
    }

    private var previewHealthy: Bool {
        guard let health = telemetry?.previewHealth, health.framesSent > 0 else {
            return telemetry?.phase != .failed
        }
        return health.isHealthy
    }
}
