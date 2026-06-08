import BlitzRecorderCore
import AppKit
import SwiftUI

struct BlitzReelsCreatorPage: View {
    @Bindable var access: AccessController
    @State private var licenseKey = ""
    private let sourceCodeURL = URL(string: "https://github.com/blitzreels/blitzrecorder")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                accessCard
                communityCard

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
            Text("BlitzRecorder")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text("Free for local 1080p recording. Early Price unlocks iPhone camera, 4K export, and 60 fps.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACCESS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))

            infoRow(
                symbol: access.hasActiveLicense ? "checkmark.seal.fill" : "lock.fill",
                color: BlitzUI.mint,
                title: access.hasActiveLicense ? access.accessLabel : access.upgradeTitle,
                detail: access.hasActiveLicense
                    ? "Full studio unlocked on this Mac."
                    : access.upgradeDetail
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Free: screen, Mac camera, mic, scenes, and 1080p export.")
                Text("Paid: iPhone camera, 4K export, 60 fps export, and updates through beta and v1.")
                Text("No export limit, no account, no subscription.")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.56))
            .fixedSize(horizontal: false, vertical: true)

            if let email = access.licenseEmail {
                infoRow(
                    symbol: "person.crop.circle.fill",
                    color: .white.opacity(0.72),
                    title: email,
                    detail: access.licenseID ?? "License active"
                )
            }

            activationForm
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Paste license key", text: $licenseKey)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            HStack(spacing: 10) {
                Button {
                    access.beginPurchase()
                } label: {
                    Label(
                        access.lockedFeatureName == nil
                            ? "Unlock the full studio for $39"
                            : "Unlock \(access.lockedFeatureName!) for $39",
                        systemImage: "creditcard.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    pasteLicenseKeyFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .disabled(access.isValidatingLicense)

                Button {
                    Task { await access.activateLicenseKey(licenseKey) }
                } label: {
                    if access.isValidatingLicense {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Activate", systemImage: "key.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(access.isValidatingLicense || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if access.hasActiveLicense {
                    Button {
                        Task { await access.refreshLicense() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(access.isValidatingLicense)

                    Button(role: .destructive) {
                        access.clearLicense()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
    }

    private func pasteLicenseKeyFromClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            return
        }
        licenseKey = pasted
    }

    private var communityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OPEN SOURCE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))

            infoRow(
                symbol: "curlybraces.square.fill",
                color: .white.opacity(0.72),
                title: "Source available",
                detail: "Source code is AGPL. Official signed builds use the paid license."
            )

            Text("BlitzRecorder records locally and does not require a cloud account.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: sourceCodeURL) {
                Label("Open source code", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .blitzGlassButton()
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

}
