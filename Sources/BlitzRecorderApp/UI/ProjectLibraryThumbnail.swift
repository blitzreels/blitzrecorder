import SwiftUI

struct ProjectLibraryThumbnail: View {
    struct Configuration {
        let metadata: ProjectLibraryMetadata
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let showsDuration: Bool
    }

    let configuration: Configuration

    var body: some View {
    ZStack(alignment: .bottomTrailing) {
        Color.black.opacity(0.3)
        if let thumbnail = configuration.metadata.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(width: configuration.width, height: configuration.height)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        BlitzUI.hoverFill,
                        BlitzUI.cardFill
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: configuration.metadata.sourceRoles.isDisjoint(with: ["screen", "camera"])
                    && !configuration.metadata.sourceRoles.isDisjoint(with: ["microphone", "systemAudio"])
                    ? "waveform" : "film")
                    .font(BlitzType.glyph(20))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }

        if configuration.showsDuration,
           let duration = configuration.metadata.durationSeconds {
            BlitzTimecode(configuration: .init(time: duration, duration: duration))
                .font(BlitzType.footnote.monospaced())
                .foregroundStyle(BlitzUI.primaryText)
                .padding(.horizontal, 4)
                .frame(height: 18)
                .background(.black.opacity(0.8), in: .rect(cornerRadius: 4))
                .padding(4)
        }
    }
    .frame(width: configuration.width, height: configuration.height)
    .clipShape(.rect(cornerRadius: configuration.cornerRadius))
    .overlay {
        RoundedRectangle(
            cornerRadius: configuration.cornerRadius,
            style: .continuous
        )
        .stroke(BlitzUI.panelStroke, lineWidth: 1)
    }
    }
}
