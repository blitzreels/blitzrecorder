import SwiftUI
#if canImport(AppKit)
import AppKit
public typealias BlitzPlatformColor = NSColor
#else
import UIKit
public typealias BlitzPlatformColor = UIColor

extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

/// One color with a light and a dark value. The system picks the right one for the view's appearance,
/// in SwiftUI (`color`) and in AppKit or UIKit (resolved at draw time).
public struct BlitzColorPair {
    public let light: BlitzPlatformColor
    public let dark: BlitzPlatformColor

    public init(light: BlitzPlatformColor, dark: BlitzPlatformColor) {
        self.light = light
        self.dark = dark
    }

    #if canImport(AppKit)
    public var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    public var color: Color { Color(nsColor: nsColor) }
    #else
    public var uiColor: UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    public var color: Color { Color(uiColor: uiColor) }
    #endif

    /// The same pair at different strengths per mode, e.g. glows that must stay softer on white.
    public func alpha(_ strength: BlitzColorPair.Strength) -> BlitzColorPair {
        .init(light: light.withAlphaComponent(strength.light), dark: dark.withAlphaComponent(strength.dark))
    }

    public struct Strength {
        public let light: CGFloat
        public let dark: CGFloat

        public init(light: CGFloat, dark: CGFloat) {
            self.light = light
            self.dark = dark
        }
    }
}
