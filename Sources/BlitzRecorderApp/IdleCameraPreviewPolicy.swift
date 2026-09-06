struct IdleCameraPreviewRequest {
    let appIsActive: Bool
    let windowIsVisible: Bool
    let keepsIdleCaptureResourcesActive: Bool
}

enum IdleCameraPreviewPolicy {
    static func shouldStart(_ request: IdleCameraPreviewRequest) -> Bool {
        request.appIsActive
            && request.windowIsVisible
            && request.keepsIdleCaptureResourcesActive
    }
}
