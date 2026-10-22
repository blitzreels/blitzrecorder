import BlitzRecorderDesign
import SwiftUI
import UIKit

/// A status as a dot and plain text, never a pill. Only the recording dot pulses: it is a live indicator.
struct CompanionStatusLabel: View {
    let text: String
    let tone: BlitzStatusTone
    @State private var isDimmed = false

    var body: some View {
        HStack(spacing: 8) {
            BlitzStatusDot(tone: tone, diameter: 9)
                .opacity(isDimmed ? 0.35 : 1)
                .animation(tone == .recording ? .easeInOut(duration: 0.8).repeatForever() : .default, value: isDimmed)
                .onAppear { isDimmed = tone == .recording }
                .onChange(of: tone) { _, tone in isDimmed = tone == .recording }
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
    }
}

extension Bundle {
    var blitzRecorderMacIcon: UIImage? {
        guard let url = url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}
