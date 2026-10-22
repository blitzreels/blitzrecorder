import SwiftUI

/// An app icon at any size, cut to Apple's continuous squircle. iOS icon files are full squares with opaque
/// corners the system masks away, so every icon shown inside the apps goes through this shape.
public struct BlitzAppIcon: View {
    let image: Image?
    let size: CGFloat

    public init(image: Image?, size: CGFloat) {
        self.image = image
        self.size = size
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    public var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                BlitzUI.controlFill
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { BlitzEdgeHighlight(shape: shape) }
        .accessibilityHidden(true)
    }
}
