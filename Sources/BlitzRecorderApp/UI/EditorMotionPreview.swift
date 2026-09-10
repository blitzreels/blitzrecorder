import SwiftUI

enum EditorMotionEffect {
    case smoothing(Bool)
    case clicks(Bool)
    case cursorSize(Double)
    case zoom(amount: Double, enabled: Bool)
    case cameraFollow(Bool)

    var allowsAnimation: Bool {
        switch self {
        case .smoothing(let enabled), .clicks(let enabled), .cameraFollow(let enabled): enabled
        case .zoom(_, let enabled): enabled
        case .cursorSize: false
        }
    }
}

struct EditorMotionPreview: View {
    struct Configuration {
        let effect: EditorMotionEffect
        let source: BlitzScenePreview
        let isAnimating: Bool
    }

    let configuration: Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()

    private var animates: Bool {
        configuration.isAnimating && configuration.effect.allowsAnimation && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animates)) { timeline in
            let progress = animates
                ? timeline.date.timeIntervalSince(animationStart).truncatingRemainder(dividingBy: 2.8) / 2.8
                : 0.62
            GeometryReader { geometry in
                content(.init(size: geometry.size, progress: progress))
            }
        }
        .onChange(of: animates) { _, active in
            if active { animationStart = Date() }
        }
        .accessibilityHidden(true)
    }

    private struct Frame {
        let size: CGSize
        let progress: Double

        var pulse: Double { (1 - cos(progress * .pi * 2)) / 2 }
        func point(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }
    }

    @ViewBuilder
    private func content(_ frame: Frame) -> some View {
        switch configuration.effect {
        case .smoothing(let enabled):
            ZStack {
                screen.opacity(0.24)
                motionPath(.init(frame: frame, smooth: enabled))
                cursor(.init(frame: frame, location: movementPoint(.init(progress: frame.progress, smooth: enabled)), size: 16))
            }
        case .clicks(let enabled):
            ZStack {
                screen.opacity(0.4)
                if enabled {
                    Circle()
                        .stroke(BlitzUI.mint.opacity(0.85 - frame.pulse * 0.4), lineWidth: 1.5)
                        .frame(width: 15 + frame.pulse * 20, height: 15 + frame.pulse * 20)
                        .position(frame.point(CGPoint(x: 0.51, y: 0.47)))
                    Circle()
                        .fill(BlitzUI.mint.opacity(0.18))
                        .frame(width: 16, height: 16)
                        .position(frame.point(CGPoint(x: 0.51, y: 0.47)))
                }
                cursor(.init(frame: frame, location: CGPoint(x: 0.56, y: 0.6), size: 18))
            }
        case .cursorSize(let scale):
            ZStack {
                screen.opacity(0.3)
                cursor(.init(frame: frame, location: CGPoint(x: 0.3, y: 0.55), size: 10))
                    .opacity(0.4)
                cursor(.init(frame: frame, location: CGPoint(x: 0.68, y: 0.5), size: 11 * scale))
            }
        case .zoom(let amount, let enabled):
            ZStack {
                screen
                    .scaleEffect(enabled ? 1 + (amount - 1) * frame.pulse : 1, anchor: .init(x: 0.65, y: 0.4))
                if enabled {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(BlitzUI.mint, lineWidth: 1.5)
                        .frame(width: frame.size.width * 0.42, height: frame.size.height * 0.5)
                        .position(frame.point(CGPoint(x: 0.65, y: 0.4)))
                }
            }
            .clipped()
        case .cameraFollow(let enabled):
            BlitzSceneLayoutThumbnail(
                layout: .horizontal,
                sceneLayout: cameraLayout(.init(progress: frame.pulse, enabled: enabled)),
                visibleSources: [.screen, .camera],
                preview: configuration.source
            )
        }
    }

    private var screen: some View {
        BlitzSceneThumbnailLayer(kind: .screen, image: configuration.source.screen)
    }

    private struct Cursor {
        let frame: Frame
        let location: CGPoint
        let size: Double
    }

    private func cursor(_ request: Cursor) -> some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: request.size, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
            .position(request.frame.point(request.location))
    }

    private struct MotionPath {
        let frame: Frame
        let smooth: Bool
    }

    private func motionPath(_ request: MotionPath) -> some View {
        Canvas { context, _ in
            var path = Path()
            for index in 0...40 {
                let point = movementPoint(.init(progress: Double(index) / 40, smooth: request.smooth))
                if index == 0 {
                    path.move(to: request.frame.point(point))
                } else {
                    path.addLine(to: request.frame.point(point))
                }
            }
            context.stroke(path, with: .color(request.smooth ? BlitzUI.mint : BlitzUI.secondaryText), style: .init(
                lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: request.smooth ? [] : [2, 3]
            ))
        }
    }

    private struct Movement {
        let progress: Double
        let smooth: Bool
    }

    private func movementPoint(_ request: Movement) -> CGPoint {
        let t = request.progress
        let jitter = request.smooth ? 0 : sin(t * .pi * 10) * 0.13
        return CGPoint(x: 0.15 + t * 0.7, y: 0.67 - sin(t * .pi / 2) * 0.35 + jitter)
    }

    private struct CameraMotion {
        let progress: Double
        let enabled: Bool
    }

    private func cameraLayout(_ request: CameraMotion) -> SceneLayout {
        let scale = request.enabled ? 1 - request.progress * 0.35 : 1
        let width = 0.4 * scale
        let height = 0.5 * scale
        return SceneLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            cameraFrame: CGRect(x: 0.95 - width, y: 0.05, width: width, height: height)
        )
    }
}
