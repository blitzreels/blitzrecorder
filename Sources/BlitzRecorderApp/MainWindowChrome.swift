import AppKit

enum MainWindowChrome {
    static let toolbarHeight: CGFloat = 52
    static let sidebarWidth: CGFloat = 216
    static let trafficLightsWidth: CGFloat = 78
    static let sidebarToggleWidth: CGFloat = 52
    static let studioExitWidth: CGFloat = 104

    @MainActor
    static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "BlitzRecorder.MainWindow")
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.backgroundColor = NSColor(white: 0.105, alpha: 1)
    }
}
