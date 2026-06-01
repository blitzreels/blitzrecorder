import SwiftUI

struct BlitzReelsCreatorPage: View {
    @Bindable var access: AccessController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                subscriptionCard
                creatorCard

                if !access.accessMessage.isEmpty {
                    Text(access.accessMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                footerLinks
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your plan")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text("With Pro you can save as many videos as you want. Free gives you three.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PRO")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))

            infoRow(
                symbol: access.isPro ? "checkmark.seal.fill" : "sparkles",
                color: access.isPro ? Color(red: 0.09, green: 1.0, blue: 0.65) : .white.opacity(0.55),
                title: access.accessLabel,
                detail: planDetail
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Pro lets you save as many videos as you want.")
                Text("It renews until you cancel it in your Apple settings.")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.56))
            .fixedSize(horizontal: false, vertical: true)

            if !access.isPro {
                Button {
                    Task { await access.purchaseAnnual() }
                } label: {
                    Label("Get Pro for \(access.annualPriceLabel)/year", systemImage: "creditcard.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzProminentGlassButton()
                .disabled(access.isPurchasing)

                Button {
                    Task { await access.purchaseMonthly() }
                } label: {
                    Label("Get Pro for \(access.monthlyPriceLabel)/month", systemImage: "creditcard.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzProminentGlassButton()
                .disabled(access.isPurchasing)
            }

            Button {
                Task { await access.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .blitzGlassButton()

            if access.hasAppStoreSubscription {
                Button {
                    access.openSubscriptionManagement()
                } label: {
                    Label("Manage Subscription", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzGlassButton()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var creatorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BLITZREELS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))

            infoRow(
                symbol: statusSymbol,
                color: statusColor,
                title: statusTitle,
                detail: statusDetail
            )

            Text("Already pay for BlitzReels? Sign in to get Pro for free.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)

            if access.hasBlitzReelsAccountConnection {
                Button {
                    Task { await access.refreshBlitzReelsEntitlement() }
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzGlassButton()

                Button {
                    access.disconnectBlitzReels()
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzGlassButton()
            } else {
                Button {
                    access.beginBlitzReelsSignIn()
                } label: {
                    Label("Sign in with BlitzReels", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzProminentGlassButton()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var footerLinks: some View {
        HStack(spacing: 12) {
            Link("Terms", destination: AppLinks.terms)
            Link("Privacy", destination: AppLinks.privacy)
            Link("Support", destination: AppLinks.support)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.55))
    }

    private func infoRow(
        symbol: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var planDetail: String {
        if access.isPro {
            return "You can save as many videos as you want."
        }
        if access.freeExportsRemaining == 1 {
            return "You have 1 free video left."
        }
        return "You have \(access.freeExportsRemaining) free videos left."
    }

    private var statusSymbol: String {
        if access.hasBlitzReelsEntitlement { return "checkmark.seal.fill" }
        if access.hasBlitzReelsAccountConnection { return "exclamationmark.triangle.fill" }
        return "person.crop.circle"
    }

    private var statusColor: Color {
        if access.hasBlitzReelsEntitlement {
            return Color(red: 0.09, green: 1.0, blue: 0.65)
        }
        if access.hasBlitzReelsAccountConnection {
            return .yellow
        }
        return .white.opacity(0.55)
    }

    private var statusTitle: String {
        if access.hasBlitzReelsEntitlement {
            return access.blitzReelsPlanName.map { "Free with \($0)" } ?? "Pro is on"
        }
        if access.hasBlitzReelsAccountConnection {
            return "Signed in, but no plan yet"
        }
        return "Not signed in"
    }

    private var statusDetail: String {
        if access.hasBlitzReelsEntitlement {
            return "Your BlitzReels plan turns on Pro."
        }
        if access.hasBlitzReelsAccountConnection {
            return "Changed your BlitzReels plan? Check again."
        }
        return "Sign in to link your BlitzReels account."
    }
}
