import Foundation

public enum BlitzRecorderProductIdentity {
    public static let macDisplayName = "BlitzRecorder"
    public static let companionDisplayName = "BlitzRecorder Camera"

    public static let macBundleID = "dev.blitzreels.blitzrecorder"
    public static let companionBundleID = "dev.blitzreels.blitzrecorder.camera"

    public static let landingPage = URL(string: "https://blitzrecorder.com")!
    public static let supportURL = URL(string: "https://blitzrecorder.com/support")!
    public static let privacyURL = URL(string: "https://blitzrecorder.com/privacy")!
    public static let termsURL = URL(string: "https://blitzrecorder.com/terms")!

    public static let macAppStoreURL: URL? = nil
    public static let companionAppStoreURL: URL? = nil

    public static var macInstallURL: URL {
        macAppStoreURL ?? landingPage
    }

    public static var companionInstallURL: URL {
        companionAppStoreURL ?? landingPage
    }
}
