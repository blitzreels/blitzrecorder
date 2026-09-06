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
            BlitzSymbol(configuration: .init(name: configuration.systemImage, size: 26))
                .foregroundStyle(BlitzUI.secondaryText)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text(configuration.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if let status = configuration.status {
                Text(status)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(BlitzUI.mint.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(BlitzUI.mint.opacity(0.09), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionConfiguration {
    let title: String
    let detail: String?
    let systemImage: String
}

private struct SettingsSectionModifier: ViewModifier {
    let configuration: SettingsSectionConfiguration

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                BlitzSymbol(configuration: .init(name: configuration.systemImage, size: 18))
                    .foregroundStyle(BlitzUI.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BlitzUI.primaryText)
                    if let detail = configuration.detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
            }
            .padding(.bottom, 4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(BlitzUI.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }
}

private struct SettingsRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
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
    func settingsSection(_ configuration: SettingsSectionConfiguration) -> some View {
        modifier(SettingsSectionModifier(configuration: configuration))
    }

    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }

    func settingsPageContent() -> some View {
        modifier(SettingsPageContentModifier())
    }
}
