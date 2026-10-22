import AppIntents

/// Opens BlitzRecorder Camera so the Mac can use it. Runs from the Control Center, Lock Screen and Action button
/// control, from Shortcuts and from Siri.
struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open BlitzRecorder Camera"
    static let description = IntentDescription("Opens the camera so BlitzRecorder on your Mac can use it.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
