import AppKit
import SwiftUI

struct CanvasColorPicker: View {
    struct Configuration {
        let initial: NSColor
        let onChange: (NSColor) -> Void
    }

    let configuration: Configuration
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var hexDraft: String

    static let presets: [NSColor] = [
        NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.98, green: 0.36, blue: 0.33, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.98, green: 0.82, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.50, alpha: 1),
        NSColor(srgbRed: 0.22, green: 0.56, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.56, green: 0.36, blue: 0.96, alpha: 1)
    ]

    init(configuration: Configuration) {
        self.configuration = configuration
        let rgb = configuration.initial.usingColorSpace(.sRGB) ?? .black
        _hue = State(initialValue: Double(rgb.hueComponent))
        _saturation = State(initialValue: Double(rgb.saturationComponent))
        _brightness = State(initialValue: Double(rgb.brightnessComponent))
        _hexDraft = State(initialValue: Self.hex(rgb))
    }

    private var color: NSColor {
        NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).usingColorSpace(.sRGB) ?? .black
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            shadeSquare
            hueBar
            HStack(spacing: 6) {
                ForEach(Self.presets.indices, id: \.self) { index in
                    presetButton(Self.presets[index])
                }
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: color))
                    .frame(width: 28, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(BlitzUI.panelStroke))
                Text("#")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                TextField("Hex", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(BlitzType.label.monospaced())
                    .onSubmit(applyHex)
            }
        }
        .padding(14)
        .frame(width: 236)
    }

    private var shadeSquare: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, Color(white: 1, opacity: 0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 16, height: 16)
                    .position(x: saturation * size.width, y: (1 - brightness) * size.height)
            }
            .clipShape(.rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                saturation = min(1, max(0, value.location.x / size.width))
                brightness = 1 - min(1, max(0, value.location.y / size.height))
                publish()
            })
        }
        .frame(height: 150)
        .accessibilityLabel("Saturation and brightness")
    }

    private var hueBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(.capsule)
                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 18, height: 18)
                    .offset(x: hue * (width - 18))
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hue = min(1, max(0, (value.location.x - 9) / (width - 18)))
                publish()
            })
        }
        .frame(height: 18)
        .accessibilityLabel("Hue")
    }

    private func presetButton(_ preset: NSColor) -> some View {
        Button {
            set(preset)
        } label: {
            Circle()
                .fill(Color(nsColor: preset))
                .overlay(Circle().strokeBorder(BlitzUI.panelStroke))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .accessibilityLabel("Color #\(Self.hex(preset))")
    }

    private func set(_ newColor: NSColor) {
        let rgb = newColor.usingColorSpace(.sRGB) ?? .black
        hue = Double(rgb.hueComponent)
        saturation = Double(rgb.saturationComponent)
        brightness = Double(rgb.brightnessComponent)
        publish()
    }

    private func publish() {
        hexDraft = Self.hex(color)
        configuration.onChange(color)
    }

    private func applyHex() {
        let digits = hexDraft.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            hexDraft = Self.hex(color)
            return
        }
        set(NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        ))
    }

    static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}
