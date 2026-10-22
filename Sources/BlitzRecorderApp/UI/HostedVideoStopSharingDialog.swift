import SwiftUI

struct HostedVideoStopSharingDialog {
    let stopping: Binding<HostedLibraryVideo?>
    let controller: HostedVideoShareController
    let title: String
    let hostedMessage: String
}

extension View {
    func stopSharingConfirmation(_ dialog: HostedVideoStopSharingDialog) -> some View {
        confirmationDialog(dialog.title, isPresented: Binding(
            get: { dialog.stopping.wrappedValue != nil }, set: { if !$0 { dialog.stopping.wrappedValue = nil } }),
            presenting: dialog.stopping.wrappedValue) { video in
            Button("Stop sharing", role: .destructive) { Task { await dialog.controller.stopSharing(video) } }
        } message: { video in
            Text(video.isOwnStorage
                 ? "The link stops working and the video is deleted from your Cloudflare. Your recording stays on this Mac."
                 : dialog.hostedMessage)
        }
    }
}
