import SwiftUI

struct AppearanceSettingsPage: View {
    private let theme = BlitzThemeStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SettingsPageHeader(.init(
                    title: "Appearance",
                    detail: "Every change shows here first, then across the app.",
                    status: nil
                ))

                AppearancePreview(configuration: .init(isDark: isDark, accent: theme.accent, tint: theme.tint))
                    .frame(maxWidth: 560)
                    .shadow(color: BlitzUI.elevationShadow, radius: 8, y: 3)

                group(title: "Mode") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(BlitzAppearanceMode.allCases) { mode in modeCard(mode) }
                    }
                }

                group(title: "Accent") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            ForEach(BlitzAccentTheme.allCases) { option in swatch(option) }
                        }
                        Text("Used for selection, focus and the main button. Record stays red and warnings stay amber.")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                group(title: "Background") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(BlitzSurfaceTint.allCases) { tint in toneCard(tint) }
                    }
                }
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
    }

    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
            content()
        }
    }

    private struct Card {
        let title: String
        let detail: String
        let isSelected: Bool
        let select: () -> Void
    }

    private func card<Preview: View>(_ card: Card, @ViewBuilder preview: () -> Preview) -> some View {
        Button(action: card.select) {
            VStack(alignment: .leading, spacing: 8) {
                preview()
                    .overlay {
                        RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                            .strokeBorder(card.isSelected ? BlitzUI.accent : .clear, lineWidth: 2)
                            .padding(-3)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text(card.detail)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .padding(3)
            .frame(maxWidth: 180, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .accessibilityLabel(card.title)
        .accessibilityHint(card.detail)
        .accessibilityAddTraits(card.isSelected ? [.isSelected] : [])
    }

    private func modeCard(_ mode: BlitzAppearanceMode) -> some View {
        card(.init(title: mode.title, detail: modeDetail(mode), isSelected: theme.mode == mode, select: {
            theme.mode = mode
            theme.applyAppearance()
        })) {
            let light = AppearancePreview(configuration: .init(isDark: false, accent: theme.accent, tint: theme.tint))
            let dark = AppearancePreview(configuration: .init(isDark: true, accent: theme.accent, tint: theme.tint))
            switch mode {
            case .light: light
            case .dark: dark
            case .system:
                light.overlay {
                    dark.mask { GeometryReader { proxy in Rectangle().frame(width: proxy.size.width / 2).offset(x: proxy.size.width / 2) } }
                }
            }
        }
    }

    private func modeDetail(_ mode: BlitzAppearanceMode) -> String {
        switch mode {
        case .system: "Follows your Mac"
        case .light: "Bright, like paper"
        case .dark: "Easy on the eyes"
        }
    }

    private func toneCard(_ tint: BlitzSurfaceTint) -> some View {
        card(.init(title: tint.title, detail: toneDetail(tint), isSelected: theme.tint == tint, select: { theme.tint = tint })) {
            AppearancePreview(configuration: .init(isDark: isDark, accent: theme.accent, tint: tint))
        }
    }

    private func toneDetail(_ tint: BlitzSurfaceTint) -> String {
        switch tint {
        case .neutral: "Pure greys"
        case .cool: "A hint of blue"
        case .warm: "A hint of warmth"
        }
    }

    private func swatch(_ option: BlitzAccentTheme) -> some View {
        let isSelected = theme.accent == option
        return Button { theme.accent = option } label: {
            Circle()
                .fill(LinearGradient(colors: [option.highlightPair.color, option.accentPair.color],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(BlitzType.symbol(11))
                            .foregroundStyle(option.onAccentPair.color)
                    }
                }
                .padding(3)
                .overlay { Circle().strokeBorder(isSelected ? option.accentPair.color : .clear, lineWidth: 2) }
        }
        .buttonStyle(BlitzPressButtonStyle())
        .help(option.title)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
