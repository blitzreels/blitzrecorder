import SwiftUI
import UIKit

@main
struct BlitzRecorderCameraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CameraCompanionStore()
    @State private var selectedTab: CameraCompanionTab = .recordings

    var body: some Scene {
        WindowGroup {
            CameraCompanionView(store: store, selectedTab: $selectedTab)
                .onAppear {
                    store.setKeepsDeviceAwake(true)
                }
                .onDisappear {
                    store.setKeepsDeviceAwake(false)
                }
                .onChange(of: scenePhase) { _, phase in
                    store.setKeepsDeviceAwake(phase == .active)
                }
                .task {
                    await store.start()
                }
                .onOpenURL { url in
                    selectedTab = CameraCompanionTab(url: url) ?? .recordings
                }
        }
    }
}
