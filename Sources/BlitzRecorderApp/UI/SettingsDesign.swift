import SwiftUI

struct SettingsPageHeaderConfiguration {
    let title: String
    let detail: String
    let status: SettingsPageStatus?
}

struct SettingsPageStatus {
    let title: String
    let isActive: Bool
}

struct SettingsPageHeader: View {
    let configuration: SettingsPageHeaderConfiguration

    init(_ configuration: SettingsPageHeaderConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(BlitzType.largeTitle)
                    .foregroundStyle(BlitzUI.primaryText)

                Text(configuration.detail)
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if let status = configuration.status {
                HStack(spacing: 6) {
                    BlitzStatusDot(tone: status.isActive ? .ready : .muted, diameter: 6)
                    Text(status.title)
                        .font(BlitzType.label)
                        .foregroundStyle(status.isActive ? BlitzUI.primaryText : BlitzUI.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(BlitzUI.controlFill, in: .capsule)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                BlitzSymbol(configuration: .init(name: configuration.systemImage, size: 18))
                    .symbolVariant(.fill)
                    .foregroundStyle(BlitzUI.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.title)
                        .font(BlitzType.section)
                        .foregroundStyle(BlitzUI.primaryText)
                    if let detail = configuration.detail {
                        Text(detail)
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
            }
            .padding(.bottom, 4)

            content
                .settingsCard()
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
                .font(BlitzType.callout)
                .foregroundStyle(BlitzUI.supportingText)
            Text(configuration.detail)
                .font(BlitzType.body)
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

struct SettingsStatusBadge: View {
    struct Configuration {
        let title: String
        let tone: BlitzStatusTone
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 6) {
            BlitzStatusDot(tone: configuration.tone, diameter: 5)
            Text(configuration.title)
                .font(BlitzType.captionEmphasis)
                .lineLimit(1)
        }
        .foregroundStyle(configuration.tone == .muted ? BlitzUI.secondaryText : configuration.tone.color)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(configuration.tone.color.opacity(0.08), in: .capsule)
    }
}

private struct SettingsSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius)
                    .strokeBorder(BlitzUI.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius)
                    .strokeBorder(BlitzUI.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
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
            .controlSize(.regular)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 44)
    }
}

extension View {
    func settingsSurface() -> some View {
        modifier(SettingsSurfaceModifier())
    }

    func settingsSection(_ configuration: SettingsSectionConfiguration) -> some View {
        modifier(SettingsSectionModifier(configuration: configuration))
    }

    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }

    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }

    func settingsPageContent() -> some View {
        modifier(SettingsPageContentModifier())
    }
}
