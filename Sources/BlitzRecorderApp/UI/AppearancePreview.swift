import SwiftUI

/// A miniature BlitzRecorder window drawn with one mode, accent and tone, so each Appearance option shows what it changes.
struct AppearancePreview: View {
    struct Configuration {
        let isDark: Bool
        let accent: BlitzAccentTheme
        let tint: BlitzSurfaceTint
    }

    let configuration: Configuration

    private static let canvas = CGSize(width: 480, height: 280)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.canvas.width
            window
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                .strokeBorder(BlitzUI.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func color(_ pair: BlitzColorPair) -> Color {
        Color(nsColor: configuration.isDark ? pair.dark : pair.light)
    }

    private var palette: BlitzSurfacePalette { configuration.tint.palette }

    private var window: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 104)
            list.frame(width: 136)
            detail
        }
        .background(color(palette.page))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { light in
                    Circle().fill(light.opacity(0.85)).frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 6)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color(BlitzColors.recordRed))
                .frame(height: 20)
                .overlay(alignment: .leading) { Circle().fill(.white).frame(width: 6, height: 6).padding(.leading, 8) }
            row(isSelected: true, width: 52)
            row(isSelected: false, width: 40)
            row(isSelected: false, width: 58)
            Spacer()
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color(palette.panel))
    }

    private func row(isSelected: Bool, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? color(configuration.accent.accentPair) : color(BlitzColors.tertiaryText))
                .frame(width: 9, height: 9)
            Capsule().fill(color(isSelected ? BlitzColors.primaryText : BlitzColors.secondaryText)).frame(width: width, height: 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color(BlitzColors.raisedFillTop))
                    .shadow(color: color(BlitzColors.elevationShadow), radius: 2, y: 1)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(color(BlitzColors.controlFill)).frame(height: 18)
                .padding(.bottom, 4)
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [color(palette.canvas), color(BlitzColors.strongFill)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(color(BlitzColors.primaryText)).frame(width: 54, height: 4)
                        Capsule().fill(color(BlitzColors.tertiaryText)).frame(width: 34, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(5)
                .background {
                    if index == 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color(BlitzColors.raisedFillTop))
                            .shadow(color: color(BlitzColors.elevationShadow), radius: 2, y: 1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color(palette.page))
        .shadow(color: color(BlitzColors.elevationShadow), radius: 4, x: 1)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(color(BlitzColors.primaryText)).frame(width: 150, height: 8)
            Capsule().fill(color(BlitzColors.tertiaryText)).frame(width: 96, height: 4)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color(configuration.accent.accentPair))
                    .frame(width: 58, height: 18)
                    .overlay { Capsule().fill(color(configuration.accent.onAccentPair)).frame(width: 30, height: 3) }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color(BlitzColors.raisedFillTop))
                    .frame(width: 58, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color(BlitzColors.separator), lineWidth: 1)
                    }
                    .overlay { Capsule().fill(color(BlitzColors.secondaryText)).frame(width: 30, height: 3) }
            }
            .padding(.top, 2)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color(palette.canvas))
                .overlay {
                    Circle().fill(BlitzUI.onMediaText).frame(width: 22, height: 22)
                        .overlay { Image(systemName: "play.fill").font(BlitzType.glyph(9)).foregroundStyle(.black) }
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 3) {
                        Capsule().fill(color(configuration.accent.accentPair)).frame(width: 70, height: 3)
                        Capsule().fill(color(BlitzColors.strongFill)).frame(height: 3)
                    }
                    .padding(10)
                }
                .shadow(color: color(BlitzColors.deepShadow), radius: 6, y: 3)
                .padding(.top, 4)
        }
        .padding(16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
