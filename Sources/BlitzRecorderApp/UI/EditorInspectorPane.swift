import SwiftUI

enum EditorInspectorMetrics {
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
}

struct EditorInspectorPane<Content: View, Footer: View>: View {
    struct Configuration {
        let title: String
        let detail: String
        let showsFooter: Bool
        @ViewBuilder let content: () -> Content
        @ViewBuilder let footer: () -> Footer
    }

    let configuration: Configuration

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.title)
                            .font(BlitzType.title)
                            .foregroundStyle(BlitzUI.primaryText)
                        Text(configuration.detail)
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.supportingText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    configuration.content()
                }
                .padding(.horizontal, EditorInspectorMetrics.horizontalPadding)
                .padding(.top, EditorInspectorMetrics.verticalPadding)
                .padding(.bottom, EditorInspectorMetrics.verticalPadding + BlitzScrollFade.height)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .blitzScrollFade(edges: configuration.showsFooter ? .bottom : [])
            if configuration.showsFooter {
                VStack(alignment: .leading, spacing: 10) {
                    configuration.footer()
                }
                .padding(.horizontal, EditorInspectorMetrics.horizontalPadding)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(BlitzUI.separator).frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.panelBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzButtonStyle(.secondary))
        .controlSize(.regular)
        .tint(BlitzUI.mint)
    }
}

struct EditorInspectorSection<Content: View>: View {
    struct Configuration {
        let title: String
        @ViewBuilder let content: () -> Content
    }

    let configuration: Configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(configuration.title)
                .font(BlitzType.section)
                .foregroundStyle(BlitzUI.primaryText)
                .accessibilityAddTraits(.isHeader)
            configuration.content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum BlitzScrollFade {
    static let height: CGFloat = 28
}

extension View {
    func blitzScrollFade(edges: VerticalEdge.Set) -> some View {
        mask {
            VStack(spacing: 0) {
                if edges.contains(.top) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: BlitzScrollFade.height)
                }
                Color.black
                if edges.contains(.bottom) {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: BlitzScrollFade.height)
                }
            }
        }
    }
}
