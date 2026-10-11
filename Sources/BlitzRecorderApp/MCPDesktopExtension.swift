import Foundation

enum MCPDesktopExtension {
    static var resourceDirectory: URL? {
        if let directory = Bundle.main.url(forResource: "BlitzRecorderMCPBridge", withExtension: nil) { return directory }
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "BlitzRecorderMCPBridge", withExtension: nil)
        #else
        return nil
        #endif
    }

    static func createBundle() async throws -> URL {
        guard let source = resourceDirectory else {
            throw MCPClientSetup.SetupError.message("The desktop extension is missing from this app. Reinstall BlitzRecorder.")
        }
        return try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BlitzRecorder-MCP-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent("BlitzRecorder.mcpb")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--norsrc", source.path, output.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw MCPClientSetup.SetupError.message("The desktop extension could not be prepared.")
            }
            return output
        }.value
    }
}
