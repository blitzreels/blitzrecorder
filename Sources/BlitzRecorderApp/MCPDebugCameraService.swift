#if DEBUG
import AVFoundation
import BlitzRecorderCore
import Foundation
import MCP

/// Debug-build hooks that let the iPhone end-to-end check drive the real app: status, camera choice and a
/// recorded take. Release builds never contain them.
@MainActor
final class MCPDebugCameraService {
    static let shared = MCPDebugCameraService()
    weak var coordinator: RecorderCoordinator?
    /// The latest status line the recorder showed, to explain a stuck step.
    var lastMessage: String?
    /// Opens the iPhone Camera page in the main window, for screenshots of its states.
    var showDevicesPage: (() -> Void)?

    func openDevicesPage() throws -> Status {
        showDevicesPage?()
        return try status()
    }
    /// Recent status lines from the recorder and the iPhone session, oldest first.
    private(set) var messageLog: [String] = []

    func record(_ message: String) {
        lastMessage = message
        messageLog = Array((messageLog + ["\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)"]).suffix(40))
    }

    struct Status: Codable {
        let recordingState: String
        let selectedCameraID: String?
        let isRemoteCameraSelected: Bool
        let connectionState: String?
        let devices: [Device]
        let previewFramesSent: Int64?
        let previewFramesDropped: Int64?
        let lastPreviewFrameAgeSeconds: Double?
        let isTransferActive: Bool?
        let transferredBytes: Int64?
        let expectedBytes: Int64?
        let captureWarning: String?
        let phonePhase: String?
        let thermalState: String?
        let connectionLog: [String]
        let previewFramesReceived: Int
        let detailMessage: String?
        let captureProfiles: [String]
        let messageLog: [String]
        let absence: String?
    }

    struct Device: Codable {
        let cameraID: String
        let name: String
        let status: String
        let isTrusted: Bool
        let isSelected: Bool
    }

    struct TakeReport: Codable {
        let startSeconds: Double
        let recordedSeconds: Double
        let stopToIdleSeconds: Double
        let projectPath: String
        let sources: [Source]
        let importMegabytesPerSecond: Double?
    }

    struct Source: Codable {
        let role: String
        let path: String
        let exists: Bool
        let bytes: Int64?
        let durationSeconds: Double?
        let videoCodec: String?
        let width: Int?
        let height: Int?
    }

    enum Failure: LocalizedError {
        case unavailable
        case busy(String)
        case noIPhone
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "BlitzRecorder is not ready."
            case .busy(let state): "BlitzRecorder is \(state); wait until it is idle."
            case .noIPhone: "No iPhone with BlitzRecorder Camera is visible to this Mac."
            case .timedOut(let step): "Timed out while \(step)."
            }
        }
    }

    func status() throws -> Status {
        guard let coordinator else { throw Failure.unavailable }
        let telemetry = coordinator.selectedRemoteCameraTelemetry()
        return Status(
            recordingState: "\(coordinator.state)",
            selectedCameraID: coordinator.settings.selectedCameraID,
            isRemoteCameraSelected: coordinator.isRemoteCameraSelected,
            connectionState: coordinator.selectedRemoteCameraConnectionState().map { "\($0)" },
            devices: coordinator.remoteCameraDeviceSummaries().map {
                Device(cameraID: $0.cameraID, name: $0.name, status: $0.status, isTrusted: $0.isTrusted,
                       isSelected: $0.isSelected)
            },
            previewFramesSent: telemetry?.previewHealth?.framesSent,
            previewFramesDropped: telemetry?.previewHealth?.framesDropped,
            lastPreviewFrameAgeSeconds: telemetry?.previewHealth?.lastFrameAgeSeconds,
            isTransferActive: telemetry?.previewHealth?.isTransferActive,
            transferredBytes: telemetry?.transferProgress?.transferredByteCount,
            expectedBytes: telemetry?.transferProgress?.expectedByteCount,
            captureWarning: telemetry?.captureWarning,
            phonePhase: telemetry.map { $0.phase.rawValue },
            thermalState: telemetry?.thermalState,
            connectionLog: coordinator.remoteCamera.connectionLog,
            previewFramesReceived: coordinator.remoteCamera.previewFramesReceived,
            detailMessage: lastMessage,
            captureProfiles: (coordinator.selectedRemoteCameraCapabilities()?.supportedCaptureProfiles ?? []).map {
                "\($0.id.rawValue): \($0.isAvailable ? "available" : $0.unavailableReason ?? "unavailable") \($0.supportedFormatIDs)"
            },
            messageLog: messageLog,
            absence: coordinator.selectedRemoteCameraAbsence().map {
                "\($0.statusLabel) | \($0.title(deviceName: coordinator.selectedRemoteCameraName() ?? "iPhone")) | \($0.instruction)"
            }
        )
    }

    func selectIPhone() throws -> Status {
        guard let coordinator else { throw Failure.unavailable }
        coordinator.startRemoteCameraDiscoveryIfNeeded()
        guard let device = coordinator.remoteCameraDeviceSummaries().first else { throw Failure.noIPhone }
        coordinator.setCamera(id: device.cameraID)
        return try status()
    }

    struct TakeRequest {
        let seconds: Double
        /// Simulates a Wi‑Fi loss this many seconds into the take; nil records without one.
        let dropAfterSeconds: Double?
        let offlineSeconds: Double
    }

    /// Chooses a Mac-attached camera, such as Continuity Camera, by part of its name.
    func selectLocalCamera(nameContains name: String) throws -> Status {
        guard let coordinator else { throw Failure.unavailable }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        guard let device = devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains(name) }) else {
            throw Failure.timedOut("finding a camera named \(name); found \(devices.map(\.localizedName))")
        }
        coordinator.setCamera(id: device.uniqueID)
        return try status()
    }

    /// Sets the iPhone codec (automatic, highEfficiency, proRes422) and color (standard, appleLog, appleLog2).
    func applyIPhoneCapture(profile: String?, color: String?) async throws -> Status {
        guard let coordinator else { throw Failure.unavailable }
        if let profile, let id = RemoteCameraCaptureProfileID(rawValue: profile) {
            coordinator.remoteCamera.applySettingsIntent(.captureProfile(id))
        }
        if let color, let mode = RemoteCameraColorMode(rawValue: color) {
            coordinator.remoteCamera.applySettingsIntent(.colorMode(mode))
        }
        try await Task.sleep(for: .seconds(4))
        return try status()
    }

    struct ControlReport: Codable {
        let requested: RemoteCameraSettings?
        let applied: RemoteCameraSettings?
        let message: String?
    }

    struct ControlRequest {
        let control: String
        let value: String
    }

    /// Sends one camera control the way the Mac controls do, then reports what the iPhone says it applied.
    func applyIPhoneControl(_ request: ControlRequest) async throws -> ControlReport {
        guard let coordinator else { throw Failure.unavailable }
        let value = request.value
        let number = Double(value)
        let intent: RemoteCameraSettingsIntent? = switch request.control {
        case "lens": RemoteCameraLens(rawValue: value).map { .lens($0) }
        case "format": Self.formatIntent(value)
        case "focusMode": RemoteCameraFocusMode(rawValue: value).map { .focusMode($0) }
        case "focusPosition": number.map { .focusPosition($0) }
        case "exposureMode": RemoteCameraExposureMode(rawValue: value).map { .exposureMode($0) }
        case "exposureBias": number.map { .exposureBias($0) }
        case "iso": .iso(number)
        case "shutter": .shutterDuration(number)
        case "whiteBalanceMode": RemoteCameraWhiteBalanceMode(rawValue: value).map { .whiteBalanceMode($0) }
        case "whiteBalance": number.map { .whiteBalance(temperature: $0, tint: 0) }
        case "stabilization": RemoteCameraStabilizationMode(rawValue: value).map { .stabilizationMode($0) }
        case "rotation": Int(value).map { .rotationDegrees($0) }
        case "autoRotation": .automaticRotation(value == "true")
        case "cinematic": .cinematicVideoEnabled(value == "true")
        case "aperture": number.map { .cinematicAperture($0) }
        case "resetImage": .resetImageSettings
        default: nil
        }
        guard let intent else { throw Failure.timedOut("reading control \(request.control)=\(value)") }
        lastMessage = nil
        coordinator.remoteCamera.applySettingsIntent(intent)
        try await Task.sleep(for: .seconds(3))
        return ControlReport(
            requested: coordinator.remoteCamera.selectedRemoteServiceID().map { coordinator.remoteCamera.remoteSettings(for: $0) },
            applied: coordinator.selectedRemoteCameraTelemetry()?.activeSettings,
            message: lastMessage
        )
    }

    static let testTakeTitle = "iPhone end-to-end check"

    /// Moves every take the end-to-end check recorded to the Trash, through the library's own delete.
    func trashTestTakes() throws -> [String] {
        guard let coordinator else { throw Failure.unavailable }
        let entries = coordinator.projectLibrary.reload(settings: coordinator.settings)
            .filter { $0.title == Self.testTakeTitle }
        var trashed: [String] = []
        for entry in entries {
            try TakeFileStore().deleteProject(.init(project: entry, settings: coordinator.settings, disposition: .trash))
            trashed.append(entry.takeDirectoryPath)
        }
        coordinator.projectLibrary.reload(settings: coordinator.settings)
        return trashed
    }

    /// "3840x2160@30" → the format and frame rate.
    private static func formatIntent(_ value: String) -> RemoteCameraSettingsIntent? {
        let parts = value.split(separator: "@")
        guard parts.count == 2, let frameRate = Int(parts[1]) else { return nil }
        return .format(id: String(parts[0]), frameRate: frameRate)
    }

    func recordTake(_ request: TakeRequest) async throws -> TakeReport {
        let seconds = request.seconds
        guard let coordinator else { throw Failure.unavailable }
        guard coordinator.state == .idle else { throw Failure.busy("\(coordinator.state)") }
        let previousTake = coordinator.lastTake?.projectURL
        let clock = ContinuousClock()
        let started = clock.now
        coordinator.start(takeTitle: Self.testTakeTitle)
        do {
            try await waitUntil("starting the recording", timeout: 30) { coordinator.state == .recording }
        } catch {
            throw Failure.timedOut("starting the recording (state \(coordinator.state), \(lastMessage ?? "no message"))")
        }
        let startSeconds = Self.seconds(started.duration(to: clock.now))
        let recordingStarted = clock.now
        if let dropAfter = request.dropAfterSeconds, dropAfter < seconds {
            try await Task.sleep(for: .seconds(dropAfter))
            coordinator.remoteCamera.debugDropConnection(seconds: request.offlineSeconds)
            try await Task.sleep(for: .seconds(seconds - dropAfter))
        } else {
            try await Task.sleep(for: .seconds(seconds))
        }
        coordinator.stop()
        let stopped = clock.now
        let recordedSeconds = Self.seconds(recordingStarted.duration(to: stopped))
        try await waitUntil("finishing and importing the take", timeout: 900) { coordinator.state == .idle }
        let stopToIdleSeconds = Self.seconds(stopped.duration(to: clock.now))
        guard let take = coordinator.lastTake, take.projectURL != previousTake else {
            throw Failure.timedOut("saving the take")
        }
        let project = try TakeFileStore().loadRecordingProject(at: take.projectURL)
        var sources: [Source] = []
        for file in project.sources {
            sources.append(await Self.inspect(role: file.role, path: file.path, exists: file.exists))
        }
        let cameraBytes = sources.first { $0.role == "camera" }?.bytes
        return TakeReport(
            startSeconds: startSeconds,
            recordedSeconds: recordedSeconds,
            stopToIdleSeconds: stopToIdleSeconds,
            projectPath: take.projectURL.path,
            sources: sources,
            importMegabytesPerSecond: cameraBytes.map { Double($0) / 1_000_000 / max(stopToIdleSeconds, 0.001) }
        )
    }

    private func waitUntil(_ step: String, timeout: Double, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure.timedOut(step) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func inspect(role: String, path: String, exists: Bool) async -> Source {
        let url = URL(fileURLWithPath: path)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let size = try? await track?.load(.naturalSize)
        let codec = try? await track?.load(.formatDescriptions).first.map {
            EditorMediaTechnicalMetadata.videoCodecLabel(CMFormatDescriptionGetMediaSubType($0))
        }
        return Source(
            role: role, path: path, exists: exists, bytes: bytes,
            durationSeconds: duration.flatMap { $0.isFinite ? $0 : nil },
            videoCodec: codec ?? nil, width: size.map { Int($0.width) }, height: size.map { Int($0.height) }
        )
    }
}

extension BlitzRecorderMCPServer {
    nonisolated static let debugTools: [Tool] = [
        Tool(
            name: "debug_iphone_status",
            title: "iPhone camera status (debug)",
            description: "Connection, live preview health, transfer progress and warnings for the BlitzRecorder Camera iPhone.",
            inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false])
        ),
        Tool(
            name: "debug_iphone_select",
            title: "Use the iPhone camera (debug)",
            description: "Choose the first visible BlitzRecorder Camera iPhone as the recording camera.",
            inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false])
        ),
        Tool(
            name: "debug_camera_select",
            title: "Use a Mac camera (debug)",
            description: "Choose a camera attached to this Mac, such as Continuity Camera, by part of its name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object(["name": .object(["type": "string"])]),
                "required": ["name"],
                "additionalProperties": false,
            ])
        ),
        Tool(
            name: "debug_iphone_capture",
            title: "Set iPhone codec and color (debug)",
            description: "profile: automatic, highEfficiency, proRes422. color: standard, appleLog, appleLog2.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "profile": .object(["type": "string"]),
                    "color": .object(["type": "string"]),
                ]),
                "additionalProperties": false,
            ])
        ),
        Tool(
            name: "debug_iphone_control",
            title: "Use an iPhone camera control (debug)",
            description: "Send one iPhone camera control from the Mac and report what the iPhone applied.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "control": .object(["type": "string"]),
                    "value": .object(["type": "string"]),
                ]),
                "required": ["control", "value"],
                "additionalProperties": false,
            ])
        ),
        Tool(
            name: "debug_trash_test_takes",
            title: "Trash end-to-end test takes (debug)",
            description: "Move every take titled 'iPhone end-to-end check' to the Trash.",
            inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false])
        ),
        Tool(
            name: "debug_show_iphone_page",
            title: "Show the iPhone Camera page (debug)",
            description: "Open the iPhone Camera page in the main window.",
            inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false])
        ),
        Tool(
            name: "debug_record_take",
            title: "Record a test take (debug)",
            description: "Record for the given seconds, stop, wait for the iPhone clip to import, and report every source file.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "seconds": .object(["type": "number", "description": "Recording length, 2 to 600 seconds."]),
                    "dropAfterSeconds": .object(["type": "number", "description": "Drop the iPhone connection this many seconds into the take, like a Wi‑Fi loss."]),
                    "offlineSeconds": .object(["type": "number", "description": "How long the connection stays down. Default 10."]),
                ]),
                "required": ["seconds"],
                "additionalProperties": false,
            ])
        ),
    ]

    nonisolated static func callDebugTool(_ parameters: CallTool.Parameters) async -> CallTool.Result? {
        let service = await MCPDebugCameraService.shared
        do {
            switch parameters.name {
            case "debug_iphone_status":
                return try Self.debugResult(await service.status())
            case "debug_iphone_select":
                return try Self.debugResult(await service.selectIPhone())
            case "debug_camera_select":
                let name = parameters.arguments?["name"]?.stringValue ?? ""
                return try Self.debugResult(await service.selectLocalCamera(nameContains: name))
            case "debug_iphone_capture":
                return try Self.debugResult(await service.applyIPhoneCapture(
                    profile: parameters.arguments?["profile"]?.stringValue,
                    color: parameters.arguments?["color"]?.stringValue
                ))
            case "debug_iphone_control":
                return try Self.debugResult(await service.applyIPhoneControl(.init(
                    control: parameters.arguments?["control"]?.stringValue ?? "",
                    value: parameters.arguments?["value"]?.stringValue ?? ""
                )))
            case "debug_trash_test_takes":
                return try Self.debugResult(await service.trashTestTakes())
            case "debug_show_iphone_page":
                return try Self.debugResult(await service.openDevicesPage())
            case "debug_record_take":
                let number: (String) -> Double? = { key in
                    let raw = parameters.arguments?[key]
                    return raw?.doubleValue ?? raw?.intValue.map(Double.init)
                }
                return try Self.debugResult(await service.recordTake(.init(
                    seconds: min(600, max(2, number("seconds") ?? 10)),
                    dropAfterSeconds: number("dropAfterSeconds"),
                    offlineSeconds: number("offlineSeconds") ?? 10
                )))
            default:
                return nil
            }
        } catch {
            return Self.errorResult(error.localizedDescription)
        }
    }

    nonisolated private static func debugResult<Output: Encodable>(_ output: Output) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(output), as: UTF8.self)
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }
}
#endif
