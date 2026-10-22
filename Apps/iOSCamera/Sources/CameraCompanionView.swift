import BlitzRecorderCore
import BlitzRecorderDesign
import SwiftUI

enum CameraCompanionTab: Hashable {
    case recordings
    case library

    init?(url: URL) {
        guard url.scheme == RemoteCameraConstants.companionURLScheme else {
            return nil
        }

        switch url.host?.lowercased() {
        case "library":
            self = .library
        default:
            self = .recordings
        }
    }
}

struct CameraCompanionView: View {
    @Bindable var store: CameraCompanionStore
    @Binding var selectedTab: CameraCompanionTab
    @State private var showsDiagnostics = false
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false

    var body: some View {
        let presentation = store.cameraPresentation
        TabView(selection: $selectedTab) {
            Tab("Camera", systemImage: "camera", value: CameraCompanionTab.recordings) {
                cameraTab(presentation)
            }
            Tab("Clips", systemImage: BlitzSymbols.library, value: CameraCompanionTab.library) {
                CameraMediaLibraryView(store: store)
            }
        }
        .tint(BlitzUI.accent)
        .preferredColorScheme(selectedTab == .recordings ? .dark : nil)
        .sheet(isPresented: $showsDiagnostics) {
            ConnectionDiagnosticsView(store: store)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding && !store.hasPairedMac && store.pairingStep == .waitingForMac },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            CompanionOnboardingView(finish: { hasCompletedOnboarding = true })
        }
        .onChange(of: presentation.isRecording) { _, isRecording in
            if isRecording { selectedTab = .recordings }
        }
    }

    private func cameraTab(_ presentation: CompanionCameraPresentation) -> some View {
        // The overlay stays inside the safe area; the camera fills behind it.
        CompanionCameraOverlay(presentation: presentation, actions: .init(
            approveMac: { store.approvePendingMac() },
            useCode: { store.pairPendingMacWithCode() },
            declineMac: { store.declinePendingMac() },
            findMac: { store.retryConnection() },
            showDetails: { showsDiagnostics = true },
            stop: { store.stopFromPhone() },
            openClips: { selectedTab = .library }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { cameraBackground }
        .toolbarVisibility(presentation.isRecording ? .hidden : .automatic, for: .tabBar)
        .statusBarHidden(presentation.isRecording)
    }

    @ViewBuilder
    private var cameraBackground: some View {
        if store.isLiveCameraPreviewEnabled {
            CameraPreview(
                session: store.camera.session,
                focusCandidates: store.camera.cinematicFocusCandidates,
                onTap: { point in
                    store.focusCinematic(at: point, lockFocus: false)
                },
                onLongPress: { point in
                    store.focusCinematic(at: point, lockFocus: true)
                }
            )
            .ignoresSafeArea()
        } else {
            BlitzUI.canvasBackground
                .ignoresSafeArea()
        }
    }
}

#Preview("App") {
    @Previewable @State var tab = CameraCompanionTab.recordings
    CameraCompanionView(store: CameraCompanionStore(), selectedTab: $tab)
}
