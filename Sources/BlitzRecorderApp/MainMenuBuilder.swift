import AppKit

@MainActor
final class MainMenuBuilder {
    private weak var coordinator: RecorderCoordinator?
    private weak var target: AnyObject?
    private var displayOptions: [SourceOption] = []
    private var cameraOptions: [SourceOption] = []
    private var microphoneOptions: [SourceOption] = []

    init(coordinator: RecorderCoordinator, target: AnyObject) {
        self.coordinator = coordinator
        self.target = target
    }

    func install() {
        rebuild()
    }

    func refreshDevices() {
        guard let coordinator else { return }
        Task { @MainActor in
            self.displayOptions = await coordinator.availableDisplays()
            self.cameraOptions = coordinator.availableCameras()
            self.microphoneOptions = coordinator.availableMicrophones()
            self.rebuild()
        }
    }

    func rebuild() {
        let menu = NSMenu()
        menu.addItem(applicationMenuItem())
        menu.addItem(fileMenuItem())
        menu.addItem(editMenuItem())
        menu.addItem(captureMenuItem())
        menu.addItem(viewMenuItem())
        menu.addItem(windowMenuItem())
        menu.addItem(helpMenuItem())
        NSApp.mainMenu = menu
    }

    private func applicationMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "BlitzRecorder")
        submenu.addItem(menuItem("About BlitzRecorder", action: #selector(MenuActionsTarget.showAbout)))
        submenu.addItem(menuItem("Check for Updates…", action: #selector(MenuActionsTarget.checkForUpdates)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Settings…", action: #selector(MenuActionsTarget.showSettings), keyEquivalent: ","))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Hide BlitzRecorder", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", target: NSApp))
        let hideOthers = menuItem("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h", target: NSApp)
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(hideOthers)
        submenu.addItem(menuItem("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Quit BlitzRecorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))
        item.submenu = submenu
        return item
    }

    private func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "File")
        submenu.addItem(menuItem("Open Output Folder", action: #selector(MenuActionsTarget.openOutputFolder), keyEquivalent: "o"))
        submenu.addItem(menuItem("Reveal Last Take", action: #selector(MenuActionsTarget.revealLastTake)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Choose Output Folder…", action: #selector(MenuActionsTarget.chooseOutputFolder)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w", target: nil))
        item.submenu = submenu
        return item
    }

    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")
        // Undo/Redo are intentionally omitted: the app has no undo manager, so they only ever
        // applied inside the transient iPhone pairing-code field and were disabled everywhere else.
        // Cut/Copy/Paste/Select All stay so ⌘X/⌘C/⌘V keep working in that field.
        submenu.addItem(menuItem("Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x", usesResponderChain: true))
        submenu.addItem(menuItem("Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c", usesResponderChain: true))
        submenu.addItem(menuItem("Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v", usesResponderChain: true))
        submenu.addItem(menuItem("Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", usesResponderChain: true))
        item.submenu = submenu
        return item
    }

    private func captureMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Capture")

        let state = coordinator?.state ?? .idle
        let readiness = coordinator?.recordingReadiness()
        let canStart = readiness?.isReady ?? false

        let start = menuItem("Start Recording", action: #selector(MenuActionsTarget.startRecording), keyEquivalent: "r")
        start.isEnabled = state == .idle && canStart
        submenu.addItem(start)

        let pauseTitle = state == .paused ? "Resume Recording" : "Pause Recording"
        let pauseSel: Selector = state == .paused ? #selector(MenuActionsTarget.resumeRecording) : #selector(MenuActionsTarget.pauseRecording)
        let pause = menuItem(pauseTitle, action: pauseSel, keyEquivalent: "p")
        pause.isEnabled = state == .recording || state == .paused
        submenu.addItem(pause)

        let stop = menuItem("Stop Recording", action: #selector(MenuActionsTarget.stopRecording), keyEquivalent: "s")
        stop.isEnabled = state == .recording || state == .paused
        submenu.addItem(stop)

        submenu.addItem(.separator())

        submenu.addItem(deviceSubmenu(
            title: "Display",
            options: displayOptions,
            selectedID: coordinator?.settings.selectedDisplayID,
            chooseAction: #selector(MenuActionsTarget.chooseDisplayItem(_:)),
            pickAction: #selector(MenuActionsTarget.pickScreen)
        ))
        submenu.addItem(deviceSubmenu(
            title: "Camera",
            options: cameraOptions,
            selectedID: coordinator?.settings.selectedCameraID,
            chooseAction: #selector(MenuActionsTarget.chooseCameraItem(_:))
        ))
        submenu.addItem(deviceSubmenu(
            title: "Microphone",
            options: microphoneOptions,
            selectedID: coordinator?.settings.selectedMicrophoneID,
            chooseAction: #selector(MenuActionsTarget.chooseMicrophoneItem(_:))
        ))

        submenu.addItem(.separator())

        let fitWindow = menuItem("Fit Front Window for Shorts", action: #selector(MenuActionsTarget.fitFrontWindowForShorts), keyEquivalent: "f")
        fitWindow.keyEquivalentModifierMask = [.command, .shift]
        submenu.addItem(fitWindow)

        submenu.addItem(.separator())

        for layout in CaptureLayout.allCases {
            let labelText = "\(layout.titleLabel) — \(layout.shortLabel)"
            let layoutItem = menuItem(labelText, action: #selector(MenuActionsTarget.chooseLayoutItem(_:)))
            layoutItem.representedObject = layout.rawValue
            layoutItem.state = coordinator?.settings.layout == layout ? .on : .off
            layoutItem.isEnabled = state == .idle
            submenu.addItem(layoutItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Merge Last Take…", action: #selector(MenuActionsTarget.mergeLastTake)))

        item.submenu = submenu
        return item
    }

    private func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "View")
        submenu.addItem(menuItem("Toggle Rule of Thirds", action: #selector(MenuActionsTarget.toggleRuleOfThirds)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Zoom In", action: #selector(MenuActionsTarget.zoomIn), keyEquivalent: "+"))
        submenu.addItem(menuItem("Zoom Out", action: #selector(MenuActionsTarget.zoomOut), keyEquivalent: "-"))
        submenu.addItem(menuItem("Reset Zoom", action: #selector(MenuActionsTarget.resetZoom), keyEquivalent: "0"))
        item.submenu = submenu
        return item
    }

    private func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Window")
        submenu.addItem(menuItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m", target: nil))
        submenu.addItem(menuItem("Zoom", action: #selector(NSWindow.performZoom(_:)), target: nil))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
        NSApp.windowsMenu = submenu
        item.submenu = submenu
        return item
    }

    private func helpMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Help")
        submenu.addItem(menuItem("BlitzRecorder Help", action: #selector(MenuActionsTarget.openHelp)))
        submenu.addItem(menuItem("Release Notes", action: #selector(MenuActionsTarget.openReleaseNotes)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Report an Issue…", action: #selector(MenuActionsTarget.reportIssue)))
        submenu.addItem(menuItem("Send Feedback…", action: #selector(MenuActionsTarget.sendFeedback)))
        submenu.addItem(menuItem("Copy Diagnostics", action: #selector(MenuActionsTarget.copyDiagnostics)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Privacy Policy", action: #selector(MenuActionsTarget.openPrivacyPolicy)))
        NSApp.helpMenu = submenu
        item.submenu = submenu
        return item
    }

    private func deviceSubmenu(
        title: String,
        options: [SourceOption],
        selectedID: String?,
        chooseAction: Selector,
        pickAction: Selector? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let recordingActive = coordinator?.state != .idle

        if options.isEmpty {
            let empty = menuItem("No devices available", action: nil)
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let defaultItem = menuItem("Default", action: chooseAction)
            defaultItem.representedObject = String?.none as Any
            defaultItem.state = selectedID == nil ? .on : .off
            defaultItem.isEnabled = !recordingActive
            submenu.addItem(defaultItem)
            submenu.addItem(.separator())

            for option in options {
                let optionItem = menuItem(option.name, action: chooseAction)
                optionItem.representedObject = option.id
                optionItem.state = option.id == selectedID ? .on : .off
                optionItem.isEnabled = !recordingActive
                submenu.addItem(optionItem)
            }
        }

        if let pickAction {
            submenu.addItem(.separator())
            let pick = menuItem("Pick Screen…", action: pickAction)
            pick.isEnabled = !recordingActive
            submenu.addItem(pick)
        }

        item.submenu = submenu
        return item
    }

    private func menuItem(
        _ title: String,
        action: Selector?,
        keyEquivalent: String = "",
        target: AnyObject? = nil,
        usesResponderChain: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if usesResponderChain {
            item.target = nil
        } else if let target {
            item.target = target
        } else if action != nil {
            item.target = self.target
        }
        return item
    }
}

@MainActor
@objc protocol MenuActionsTarget: AnyObject {
    func showAbout()
    func startRecording()
    func pauseRecording()
    func resumeRecording()
    func stopRecording()
    func showSettings()
    func checkForUpdates()
    func openReleaseNotes()
    func openHelp()
    func reportIssue()
    func sendFeedback()
    func copyDiagnostics()
    func openPrivacyPolicy()
    func chooseDisplayItem(_ sender: NSMenuItem)
    func chooseCameraItem(_ sender: NSMenuItem)
    func chooseMicrophoneItem(_ sender: NSMenuItem)
    func chooseLayoutItem(_ sender: NSMenuItem)
    func pickScreen()
    func toggleRuleOfThirds()
    func zoomIn()
    func zoomOut()
    func resetZoom()
    func openOutputFolder()
    func revealLastTake()
    func chooseOutputFolder()
    func mergeLastTake()
    func fitFrontWindowForShorts()
}
