import AppKit
import SwiftUI

struct BlitzPaneDivider: View {
    static let thickness: Double = 8
    struct Configuration {
        let axis: Axis
        let label: String
        let value: Binding<Double>
        let bounds: ClosedRange<Double>
        let defaultValue: Double
        let onCommit: () -> Void
    }

    let configuration: Configuration
    @State private var dragOrigin: Double?
    @State private var isHovering = false

    private var adjustsWidth: Bool { configuration.axis == .horizontal }
    private var isActive: Bool { isHovering || dragOrigin != nil }

    var body: some View {
        ZStack {
            Rectangle().fill(BlitzUI.projectLibraryBackground)
            Rectangle()
                .fill(isActive ? BlitzUI.mint.opacity(0.45) : BlitzUI.separator)
                .frame(width: adjustsWidth ? 1 : nil, height: adjustsWidth ? nil : 1)
            Capsule()
                .fill(isActive ? BlitzUI.mint : BlitzUI.secondaryText.opacity(0.45))
                .frame(width: adjustsWidth ? 3 : 28, height: adjustsWidth ? 28 : 3)
        }
        .frame(
            width: adjustsWidth ? Self.thickness : nil,
            height: adjustsWidth ? nil : Self.thickness
        )
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            update(configuration.defaultValue)
            configuration.onCommit()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = configuration.value.wrappedValue }
                    guard let dragOrigin else { return }
                    let translation = adjustsWidth ? value.translation.width : value.translation.height
                    update(dragOrigin - translation)
                }
                .onEnded { _ in
                    guard dragOrigin != nil else { return }
                    dragOrigin = nil
                    configuration.onCommit()
                }
        )
        .onHover { isHovering = $0 }
        .blitzCursor(adjustsWidth ? .resizeLeftRight : .resizeUpDown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(configuration.label)
        .accessibilityValue("\(Int(configuration.value.wrappedValue.rounded())) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: update(configuration.value.wrappedValue + 24)
            case .decrement: update(configuration.value.wrappedValue - 24)
            @unknown default: return
            }
            configuration.onCommit()
        }
        .accessibilityAction(named: "Reset size") {
            update(configuration.defaultValue)
            configuration.onCommit()
        }
        .help("Drag to resize. Double-click to reset.")
    }

    private func update(_ proposed: Double) {
        guard proposed.isFinite else { return }
        configuration.value.wrappedValue = min(
            configuration.bounds.upperBound, max(configuration.bounds.lowerBound, proposed))
    }
}
