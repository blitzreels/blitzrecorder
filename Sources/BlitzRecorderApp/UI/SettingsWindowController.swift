import AppKit
import SwiftUI

// MARK: - Settings window (⌘,)
//
// Native macOS preferences window built the way Apple recommends: an
// `NSTabViewController` with `tabStyle = .toolbar`. That gives the Mail/Safari/Xcode
// `.preference` toolbar chrome, tab selection, animated transitions, and automatic
// resize-to-fit for free — no hand-rolled toolbar/delegate/resize code.
//
// Appearance is pinned dark via the standard `NSAppearance` API (Final Cut / Logic
// style) rather than hardcoded colors, so the toolbar and standard controls still
// adopt Tahoe's Liquid Glass. Panes currently reuse the existing page views; their
// *content* gets rebuilt on native `Form`/system materials in a follow-up slice.

/// The four Settings panes, in the order they are added to the toolbar. Each removed
/// app-rail destination maps to one of these so SwiftUI views can route to a specific
/// pane (rule #5: Export -> recording, iPhone -> devices, Access -> permissions,
/// Plan -> account).
enum SettingsPane: Int, CaseIterable {
    case recording
    case devices
    case permissions
    case account
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabController: SettingsTabController

    init(viewModel: RecorderViewModel) {
        tabController = SettingsTabController(viewModel: viewModel)
        let window = NSWindow(contentViewController: tabController)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .preference
        // Fixed-size preferences window: not user-resizable (content scrolls instead of
        // letting the window shrink to nothing). Native prefs-window convention.
        window.styleMask.remove(.resizable)
        window.setContentSize(SettingsTabController.contentSize)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Selects a specific pane before showing. Panes are added in `SettingsPane`'s
    /// declaration order, so the raw value is the tab index.
    func select(_ pane: SettingsPane) {
        let index = pane.rawValue
        guard index >= 0, index < tabController.tabViewItems.count else { return }
        tabController.selectedTabViewItemIndex = index
    }
}

@MainActor
private final class SettingsTabController: NSTabViewController {
    private let viewModel: RecorderViewModel

    /// One fixed content size shared by every pane so the window never resizes or
    /// jumps when switching tabs. Panes whose content is taller than this scroll
    /// inside the fixed frame instead of resizing the window.
    static let contentSize = NSSize(width: 860, height: 720)

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []  // no crossfade — instant tab switching
        // `scrolls: false` for pages that already host their own ScrollView
        // (RemoteCameraPage, BlitzReelsCreatorPage) so we don't double-wrap; the
        // others get a ScrollView here so tall content scrolls instead of clipping.
        addPane(title: "Recording", symbol: "slider.horizontal.3", scrolls: true) {
            RecordingSettingsPage(vm: viewModel)
        }
        addPane(title: "Devices", symbol: "iphone.gen3", scrolls: false) {
            RemoteCameraPage(vm: viewModel)
        }
        addPane(title: "Permissions", symbol: "lock.shield", scrolls: true) {
            PermissionsPage(vm: viewModel)
        }
        addPane(title: "Account", symbol: "person.crop.circle", scrolls: false) {
            BlitzReelsCreatorPage(access: viewModel.accessController)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addPane<Content: View>(
        title: String,
        symbol: String,
        scrolls: Bool,
        @ViewBuilder content: () -> Content
    ) {
        let size = Self.contentSize
        let host = NSHostingController(
            rootView: PaneContainer(scrolls: scrolls, size: size, content: content)
                .preferredColorScheme(.dark)
        )
        host.title = title
        host.preferredContentSize = size

        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }
}

/// Pins a Settings pane to the shared fixed size with consistent top-leading
/// alignment. Pages that don't already scroll are wrapped in a `ScrollView`;
/// pages that scroll themselves just receive the fixed frame.
private struct PaneContainer<Content: View>: View {
    let scrolls: Bool
    let size: NSSize
    @ViewBuilder let content: Content

    init(scrolls: Bool, size: NSSize, @ViewBuilder content: () -> Content) {
        self.scrolls = scrolls
        self.size = size
        self.content = content()
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                content
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
