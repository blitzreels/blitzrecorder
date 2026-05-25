import AppKit
import SwiftUI

struct PreviewStageRepresentable: NSViewRepresentable {
    let view: PreviewStageView

    func makeNSView(context: Context) -> PreviewStageView {
        view
    }

    func updateNSView(_ nsView: PreviewStageView, context: Context) {}
}

struct CameraPreviewRepresentable: NSViewRepresentable {
    let view: CameraPreviewView

    func makeNSView(context: Context) -> CameraPreviewView {
        view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
}
