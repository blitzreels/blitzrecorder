import SwiftUI

/// The account button's popover in Shared videos: who is signed in, where links are stored, and direct actions.
struct HostedAccountPopover: View {
    @Bindable var controller: HostedVideoShareController

    private var status: String {
        switch controller.activeStorage {
        case .blitzrecorder: "BlitzRecorder Hosting"
        case .cloudflare: "Free · Your Cloudflare"
        case nil: "Free account"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BlitzAccountAvatar(configuration: .init(name: controller.account?.email ?? "BlitzRecorder", imageURL: nil, size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.account?.email ?? "BlitzRecorder account")
                        .font(BlitzType.strong).lineLimit(1).truncationMode(.middle)
                    Text(status).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .padding(14)
            if let plan = controller.plan, plan.offersSharing, !controller.canShare {
                divider
                HostedSharingPlanPicker(controller: controller, plan: plan).padding(14)
            } else if controller.cloudflare != nil {
                divider
                HostedSharingStorageSummary(controller: controller).padding(14)
            }
            divider
            VStack(spacing: 2) {
                if controller.isSubscribed {
                    action(.init(title: "Manage plan", symbol: "creditcard", destructive: false,
                                 busy: controller.accountOperation == .openingBilling)) {
                        Task { await controller.openBilling() }
                    }
                }
                action(.init(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", destructive: true,
                             busy: controller.accountOperation == .signingOut)) {
                    Task { await controller.disconnect() }
                }
                .disabled(controller.isRunning)
            }
            .padding(6)
            .disabled(controller.accountOperation != nil)
            if let message = controller.accountMessage {
                Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 14)
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(BlitzUI.primaryText)
    }

    private var divider: some View { Rectangle().fill(BlitzUI.separator).frame(height: 1) }

    private struct Action {
        let title: String
        let symbol: String
        let destructive: Bool
        let busy: Bool
    }

    private func action(_ action: Action, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol).font(BlitzType.symbol(12)).frame(width: 18)
                Text(action.title).font(BlitzType.label)
                Spacer(minLength: 8)
                if action.busy { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(action.destructive ? BlitzUI.recordRed : BlitzUI.primaryText)
            .padding(.horizontal, 8)
            .frame(height: BlitzControlMetrics.height(.small))
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
    }
}
