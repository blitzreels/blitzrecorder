import AppKit
import SwiftUI

extension AppDelegate {
    func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = appStatusImage()
        item.button?.imagePosition = .imageLeft
        item.button?.imageScaling = .scaleProportionallyDown
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        populateStatusMenu(menu)
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateStatusMenu(menu)
    }

    private func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if NowPlayingController.shared.hasMedia, coordinator.state == .idle {
            let playbackItem = NSMenuItem()
            let view = NSHostingView(rootView: NowPlayingMenuView(playback: .shared))
            view.setFrameSize(view.fittingSize)
            playbackItem.view = view
            menu.addItem(playbackItem)
            menu.addItem(.separator())
        }

        let recordingStatusItem = NSMenuItem(
            title: recordingStatusTitle(),
            action: nil,
            keyEquivalent: ""
        )
        recordingStatusItem.isEnabled = false
        recordingStatusMenuItem = recordingStatusItem
        menu.addItem(recordingStatusItem)

        switch coordinator.state {
        case .idle:
            menu.addItem(withTitle: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
        case .recording:
            menu.addItem(withTitle: "Pause Recording", action: #selector(pauseRecording), keyEquivalent: "")
            menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        case .paused:
            menu.addItem(withTitle: "Resume Recording", action: #selector(resumeRecording), keyEquivalent: "")
            menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        case .starting, .finishing:
            break
        }
        menu.addItem(withTitle: "Show BlitzRecorder", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())

        let heading = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let projects = TakeFileStore()
            .loadProjectHistory(settings: coordinator.settings)
            .entries
            .prefix(5)

        if projects.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for project in projects {
                let item = NSMenuItem(
                    title: Self.shortMenuTitle(project.title),
                    action: #selector(openRecentProject),
                    keyEquivalent: ""
                )
                item.representedObject = project
                item.isEnabled = coordinator.state == .idle
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Recordings Folder", action: #selector(openOutputFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BlitzRecorder", action: #selector(quitApplication), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func recordingStatusTitle() -> String {
        switch coordinator.state {
        case .idle:
            return "Not Recording"
        case .starting:
            return "Starting Recording..."
        case .recording:
            return "Recording \(formattedStatusElapsed())"
        case .paused:
            return "Paused \(formattedStatusElapsed())"
        case .finishing:
            return "Finishing Recording..."
        }
    }

    private func formattedStatusElapsed() -> String {
        let activeSeconds = statusElapsedStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let totalSeconds = Int((statusElapsedAccumulated + activeSeconds).rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func shortMenuTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "Untitled Recording" : trimmedTitle
        guard displayTitle.count > 30 else { return displayTitle }
        return String(displayTitle.prefix(27)) + "..."
    }

    func updateStatusItem(for state: RecordingState) {
        recordingAppIcon?.update(state)
        blinkTimer?.invalidate()
        blinkTimer = nil

        switch state {
        case .idle:
            resetStatusElapsed()
            statusItem?.button?.image = appStatusImage()
            statusItem?.button?.title = ""
        case .starting:
            resetStatusElapsed()
            statusItem?.button?.image = statusImage(color: .systemBlue)
            statusItem?.button?.title = ""
        case .recording:
            resumeStatusElapsed()
            statusItem?.button?.image = statusImage(color: .systemRed)
        case .paused:
            pauseStatusElapsed()
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.blinkOn.toggle()
                    self.statusItem?.button?.image = self.statusImage(color: self.blinkOn ? .systemRed : .clear)
                }
            }
        case .finishing:
            stopStatusElapsedTimer()
            statusItem?.button?.image = statusImage(color: .systemOrange)
        }
    }

    private func resumeStatusElapsed() {
        if statusElapsedStartedAt == nil {
            statusElapsedStartedAt = Date()
        }
        statusElapsedTimer?.invalidate()
        statusElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusElapsedTitle()
            }
        }
        updateStatusElapsedTitle()
    }

    private func pauseStatusElapsed() {
        if let statusElapsedStartedAt {
            statusElapsedAccumulated += Date().timeIntervalSince(statusElapsedStartedAt)
            self.statusElapsedStartedAt = nil
        }
        stopStatusElapsedTimer()
        updateStatusElapsedTitle()
    }

    private func resetStatusElapsed() {
        stopStatusElapsedTimer()
        statusElapsedStartedAt = nil
        statusElapsedAccumulated = 0
    }

    private func stopStatusElapsedTimer() {
        statusElapsedTimer?.invalidate()
        statusElapsedTimer = nil
    }

    private func updateStatusElapsedTitle() {
        statusItem?.button?.title = " \(formattedStatusElapsed())"
        recordingStatusMenuItem?.title = recordingStatusTitle()
    }

    private func statusImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 12, height: 12)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func appStatusImage() -> NSImage {
        let image = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    @objc private func showWindow() {
        presentMainWindow()
    }

    @objc private func openRecentProject(_ sender: NSMenuItem) {
        guard coordinator.state == .idle,
              let project = sender.representedObject as? RecordingProjectHistory.Entry else {
            return
        }
        windowController?.openProject(project)
        presentMainWindow()
    }
}
