import BlitzRecorderCore
import Foundation
import Observation

enum AppLinks {
    static let landingPage = BlitzRecorderProductIdentity.landingPage
    static let support = BlitzRecorderProductIdentity.supportURL
    static let privacy = BlitzRecorderProductIdentity.privacyURL
    static let terms = BlitzRecorderProductIdentity.termsURL
}

@Observable
@MainActor
final class AccessController {
    var accessMessage = ""

    init(defaults: UserDefaults? = nil) {}

    var canRenderExport: Bool { true }
    var canUseIPhoneCamera: Bool { true }
    var canUse4KExport: Bool { true }
    var canUse60FPSExport: Bool { true }
    var accessLabel: String { "Free" }

    func handleBlitzRecorderURL(_ url: URL) {
        guard url.scheme == "blitzrecorder" else { return }
        accessMessage = "All features are free. No account or license key is needed."
    }
}
