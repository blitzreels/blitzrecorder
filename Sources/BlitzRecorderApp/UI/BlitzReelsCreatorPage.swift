import BlitzRecorderCore
import AppKit
import SwiftUI

struct BlitzReelsCreatorPage: View {
    @Bindable var access: AccessController
    @State private var licenseKey = ""
    @FocusState private var licenseKeyFieldFocused: Bool
    private let sourceCodeURL = URL(string: "https://github.com/blitzreels/blitzrecorder")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                accessCard
                communityCard

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

            activationForm
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("License", systemImage: "key.horizontal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer(minLength: 10)

                licenseStatusPill
            }

            if access.hasActiveLicense {
                activeLicensePanel
            } else {
                licenseEntryPanel
            }

            licenseFeedback
        }
        .padding(14)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
    }

    private var licenseEntryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Paste license key", text: $licenseKey)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .focused($licenseKeyFieldFocused)
                .textSelection(.enabled)
                .onSubmit {
                    activateLicenseKey()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(licenseKeyFieldFocused ? BlitzUI.mint.opacity(0.62) : .white.opacity(0.12), lineWidth: 1)
                }

            HStack(spacing: 10) {
                Button {
                    pasteLicenseKeyFromClipboard()
                } label: {
                    Label("Paste key", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .disabled(access.isValidatingLicense)

                Button {
                    activateLicenseKey()
                } label: {
                    if access.isValidatingLicense {
                        Label("Checking license", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Activate license", systemImage: "checkmark.seal.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BlitzUI.mint)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(access.isValidatingLicense || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 0)

                Button {
                    access.beginPurchase()
                } label: {
                    Label("Buy license", systemImage: "creditcard.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .onAppear {
            guard !access.hasActiveLicense else { return }
            DispatchQueue.main.async {
                licenseKeyFieldFocused = true
            }
        }
    }

    private var activeLicensePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BlitzUI.mint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(access.licenseEmail ?? "License active")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)

                    Text(access.licenseID ?? "Early lifetime license")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 6) {
                licenseFeatureChip("iPhone camera")
                licenseFeatureChip("4K export")
                licenseFeatureChip("60 fps")
            }

            HStack(spacing: 10) {
                Button {
                    Task { await access.refreshLicense() }
                } label: {
                    Label("Refresh license", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(access.isValidatingLicense)

                Button(role: .destructive) {
                    access.clearLicense()
                    licenseKey = ""
                    licenseKeyFieldFocused = true
                } label: {
                    Label("Remove license", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private func licenseFeatureChip(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(BlitzUI.mint.opacity(0.92))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(BlitzUI.mint.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private var licenseFeedback: some View {
        if !access.accessMessage.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: licenseStatusSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(licenseStatusColor)
                    .frame(width: 14)

                Text(access.accessMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
        }
    }

    private var licenseStatusPill: some View {
        HStack(spacing: 6) {
            BlitzStatusDot(tone: access.hasActiveLicense ? .ready : (access.isValidatingLicense ? .live : .muted), diameter: 6)
            Text(licenseStatusText)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(access.hasActiveLicense || access.isValidatingLicense ? BlitzUI.mint : .white.opacity(0.58))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.055), in: Capsule())
    }

    private var licenseStatusText: String {
        if access.isValidatingLicense {
            return "Checking"
        }
        if access.hasActiveLicense {
            return "Active"
        }
        return "Not active"
    }

    private var licenseStatusSymbol: String {
        if access.isValidatingLicense { return "arrow.triangle.2.circlepath" }
        if access.hasActiveLicense { return "checkmark.circle.fill" }
        if licenseMessageLooksLikeError { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private var licenseStatusColor: Color {
        if access.isValidatingLicense || access.hasActiveLicense {
            return BlitzUI.mint
        }
        if licenseMessageLooksLikeError {
            return BlitzUI.warning
        }
        return .white.opacity(0.5)
    }

    private var licenseMessageLooksLikeError: Bool {
        let message = access.accessMessage.lowercased()
        return message.contains("couldn't")
            || message.contains("invalid")
            || message.contains("not active")
            || message.contains("different")
            || message.contains("revoked")
            || message.contains("refunded")
            || message.contains("clipboard does not")
    }

    private func pasteLicenseKeyFromClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            access.accessMessage = "Clipboard does not contain a license key."
            return
        }
        licenseKey = pasted
        licenseKeyFieldFocused = true
        access.accessMessage = "License key pasted."
    }

    private func activateLicenseKey() {
        Task {
            await access.activateLicenseKey(licenseKey)
            if access.hasActiveLicense {
                licenseKey = ""
                licenseKeyFieldFocused = false
            }
        }
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
