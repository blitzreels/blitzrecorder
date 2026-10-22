import AppIntents

/// Makes "Open BlitzRecorder Camera" available to Siri, Spotlight and the Action button without setup.
struct CameraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCameraIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Start \(.applicationName) for my Mac",
            ],
            shortTitle: "Open Camera",
            systemImageName: "iphone.rear.camera"
        )
    }
}
