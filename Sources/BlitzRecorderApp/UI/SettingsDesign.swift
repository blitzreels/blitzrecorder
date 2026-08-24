import SwiftUI

struct SettingsPageHeaderConfiguration {
    let title: String
    let detail: String
    let systemImage: String
    let status: String?
}

struct SettingsPageHeader: View {
    let configuration: SettingsPageHeaderConfiguration

    init(_ configuration: SettingsPageHeaderConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(BlitzUI.mint.opacity(0.12))
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(BlitzUI.mint.opacity(0.22), lineWidth: 1)
                Image(systemName: configuration.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.mint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))

                Text(configuration.detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if let status = configuration.status {
                Text(status)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BlitzUI.mint.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(BlitzUI.mint.opacity(0.09), in: .capsule)
                    .overlay {
                        Capsule()
                            .stroke(BlitzUI.mint.opacity(0.16), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCardConfiguration {
    let title: String
    let detail: String?
    let systemImage: String
}

private struct SettingsCardModifier: ViewModifier {
    let configuration: SettingsCardConfiguration

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: configuration.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.mint.opacity(0.80))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))

                    if let detail = configuration.detail {
                        Text(detail)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.36))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(height: 1)

            content
        }
        .background(BlitzUI.cardFill, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlitzUI.panelStroke.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 9, y: 4)
    }
}

struct SettingsRowLabelConfiguration {
    let title: String
    let detail: String
}

struct SettingsRowLabel: View {
    let configuration: SettingsRowLabelConfiguration

    init(_ configuration: SettingsRowLabelConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
            Text(configuration.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private struct SettingsRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

private struct SettingsPageContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 44)
    }
}

extension View {
    func settingsCard(_ configuration: SettingsCardConfiguration) -> some View {
        modifier(SettingsCardModifier(configuration: configuration))
    }

    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }

    func settingsPageContent() -> some View {
        modifier(SettingsPageContentModifier())
    }
}
