import SwiftUI

private struct BlitzWindowToolbarModifier: ViewModifier {
    @EnvironmentObject private var updates: AppUpdateController
    let showsUpdate: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.leading, MainWindowChrome.toolbarLeadingInset)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity)
                .frame(height: MainWindowChrome.toolbarHeight)
                .background {
                    BlitzUI.panelBackground
                        .contentShape(.rect)
                        .gesture(WindowDragGesture())
                        .allowsWindowActivationEvents(true)
                }

            if showsUpdate, updates.updateVersion != nil {
                AppUpdateBanner()
            }
        }
        .zIndex(1)
    }
}

extension View {
    func blitzWindowToolbar(showsUpdate: Bool) -> some View {
        modifier(BlitzWindowToolbarModifier(showsUpdate: showsUpdate))
    }
}
