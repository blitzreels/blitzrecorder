import Foundation

enum LocalDevelopmentRuntime {
    static func disablesIdleCapture(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["BLITZRECORDER_DISABLE_IDLE_CAPTURE"] == "1"
    }

    static func isNoninteractiveVerification(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        disablesIdleCapture(environment: environment)
    }
}
