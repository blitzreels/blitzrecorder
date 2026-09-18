import Foundation
import BlitzRecorderDomain
import WindowsCapture

@main
enum BlitzRecorderWindows {
    struct Options {
        var outputRoot = defaultOutputRoot()
        var monitor = 0
        var mic = true
        var systemAudio = true
        var camera = false
        var headless = false
        var cropX = 0
        var cropY = 0
        var cropW = 0
        var cropH = 0
        var exportFixture: String?
        var exportTake: String?
        var playTake: String?
    }

    static var options = Options()

    static func main() {
        #if os(Windows)
        let cli = Set(["-h", "--help", "--headless", "--export-fixture", "--export", "--play"])
        if CommandLine.arguments.contains(where: { cli.contains($0) }) {
            br_attach_parent_console()
        }
        #endif
        guard parseArguments() else { return }

        if let directory = options.exportFixture {
            do {
                try exportFixture(to: directory)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            }
            return
        }

        if let directory = options.exportTake {
            composeTake(at: directory)
            return
        }

        if let take = options.playTake {
            playTake(at: take)
            return
        }

        if !options.headless {
            let root = options.outputRoot
            let prepare: br_prepare_take_fn = prepareTake
            let code = root.withCString { pointer in
                br_studio_run(pointer, Int32(options.monitor), prepare, nil)
            }
            if code == 0 {
                return
            }
            #if os(Windows)
            br_attach_parent_console()
            #endif
            print(String(cString: br_capture_last_error()))
            print("falling back to console. Type start / stop / quit.")
        }

        runConsole()
    }

    static func parseArguments() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            print("BlitzRecorderWindows [--output DIR] [--monitor N] [--area X,Y,W,H] [--no-mic] [--camera] [--no-system-audio] [--headless] [--export-fixture DIR] [--export TAKE_DIR] [--play TAKE_DIR]")
            return false
        }
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--output", index + 1 < arguments.count {
                options.outputRoot = arguments[index + 1]
                index += 2
                continue
            }
            if argument == "--monitor", index + 1 < arguments.count {
                options.monitor = Int(arguments[index + 1]) ?? 0
                index += 2
                continue
            }
            if argument == "--export-fixture", index + 1 < arguments.count {
                options.exportFixture = arguments[index + 1]
                index += 2
                continue
            }
            if argument == "--export", index + 1 < arguments.count {
                options.exportTake = arguments[index + 1]
                index += 2
                continue
            }
            if argument == "--play", index + 1 < arguments.count {
                options.playTake = arguments[index + 1]
                index += 2
                continue
            }
            if argument == "--no-mic" {
                options.mic = false
                index += 1
                continue
            }
            if argument == "--mic" {
                options.mic = true
                index += 1
                continue
            }
            if argument == "--camera" {
                options.camera = true
                index += 1
                continue
            }
            if argument == "--no-system-audio" {
                options.systemAudio = false
                index += 1
                continue
            }
            if argument == "--area", index + 1 < arguments.count {
                let parts = arguments[index + 1]
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count != 4 || parts[2] < 16 || parts[3] < 16 {
                    FileHandle.standardError.write(Data("area needs X,Y,W,H with even crop at least 16x16\n".utf8))
                    return false
                }
                options.cropX = parts[0]
                options.cropY = parts[1]
                options.cropW = parts[2] & ~1
                options.cropH = parts[3] & ~1
                index += 2
                continue
            }
            if argument == "--headless" {
                options.headless = true
                index += 1
                continue
            }
            FileHandle.standardError.write(Data("unknown argument: \(argument)\n".utf8))
            return false
        }
        return true
    }

    static func runConsole() {
        print("output=\(options.outputRoot) monitor=\(options.monitor) area=\(options.cropW)x\(options.cropH)+\(options.cropX)+\(options.cropY) systemAudio=\(options.systemAudio) mic=\(options.mic) camera=\(options.camera)")
        var recording = false
        while let line = readLine() {
            let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if command == "quit" || command == "exit" {
                if recording {
                    _ = br_capture_stop()
                }
                return
            }
            if command == "stop" {
                let code = br_capture_stop()
                recording = false
                print(code == 0 ? "stopped" : String(cString: br_capture_last_error()))
                continue
            }
            if command != "start" {
                print("commands: start, stop, quit")
                continue
            }
            if recording {
                print("already recording")
                continue
            }
            do {
                let takeURL = try makeTakeDirectory(root: options.outputRoot)
                try writeTakeSidecars(
                    takeURL: takeURL,
                    microphone: options.mic,
                    systemAudio: options.systemAudio,
                    camera: options.camera
                )
                let code = nativePath(takeURL).withCString { path in
                    br_capture_start(
                        path,
                        Int32(options.monitor),
                        options.systemAudio ? 1 : 0,
                        options.mic ? 1 : 0,
                        options.camera ? 1 : 0,
                        nil,
                        Int32(options.cropX),
                        Int32(options.cropY),
                        Int32(options.cropW),
                        Int32(options.cropH)
                    )
                }
                if code != 0 {
                    print(String(cString: br_capture_last_error()))
                    continue
                }
                recording = true
                let warning = String(cString: br_capture_last_error())
                if warning.isEmpty {
                    print("recording \(takeURL.path)")
                } else {
                    print("recording \(takeURL.path) — \(warning)")
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    static func exportFixture(to directory: String) throws {
        let takeURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: takeURL, withIntermediateDirectories: true)
        let scene = PortableSceneLayout.screenWithCameraPip
        try writeTakeSidecars(takeURL: takeURL, microphone: true, systemAudio: false, camera: true)
        let pip = scene.camera ?? .cameraPip
        let code = nativePath(takeURL).withCString { path in
            br_export_composed_fixture(
                path,
                Int32(1280),
                Int32(720),
                pip.x,
                pip.y,
                pip.width,
                pip.height,
                90,
                30
            )
        }
        if code != 0 {
            throw NSError(
                domain: "BlitzRecorderWindows",
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: String(cString: br_capture_last_error())]
            )
        }
        print("exported fixture \(takeURL.path) encoder=\(String(cString: br_last_video_encoder()))")
    }

    static func composeTake(at directory: String) {
        let takeURL = URL(fileURLWithPath: directory, isDirectory: true)
        let screen = takeURL.appendingPathComponent(TakeFolderLayout.screenName)
        let camera = takeURL.appendingPathComponent(TakeFolderLayout.cameraName)
        let exported = takeURL.appendingPathComponent(TakeFolderLayout.exportName)
        let project = (try? TakeJSON.read(
            PortableProject.self,
            from: takeURL.appendingPathComponent(TakeFolderLayout.projectName)
        )) ?? PortableProject.screenAndAudio(hasMicrophone: false, hasSystemAudio: false, hasCamera: false)
        let pip = project.scene.camera ?? NormalizedRect.cameraPip
        let cameraPath = fileExists(camera) ? nativePath(camera) : ""
        let code = nativePath(screen).withCString { screenPointer in
            cameraPath.withCString { cameraPointer in
                nativePath(exported).withCString { exportPointer in
                    br_compose_take(
                        screenPointer,
                        cameraPointer,
                        exportPointer,
                        pip.x,
                        pip.y,
                        pip.width,
                        pip.height
                    )
                }
            }
        }
        if code != 0 {
            print(String(cString: br_capture_last_error()))
            return
        }
        print("composed \(exported.path) encoder=\(String(cString: br_last_video_encoder()))")
    }

    static func playTake(at directory: String) {
        let takeURL = URL(fileURLWithPath: directory, isDirectory: true)
        let screen = takeURL.appendingPathComponent(TakeFolderLayout.screenName)
        let camera = takeURL.appendingPathComponent(TakeFolderLayout.cameraName)
        let mic = takeURL.appendingPathComponent(TakeFolderLayout.microphoneName)
        let systemAudio = takeURL.appendingPathComponent(TakeFolderLayout.systemAudioName)
        let projectURL = takeURL.appendingPathComponent(TakeFolderLayout.projectName)
        let project = try? TakeJSON.read(PortableProject.self, from: projectURL)
        var ranges: [br_kept_range] = []
        if let project, !project.cuts.isEmpty {
            let map = TimelineTimeMap(takeDuration: MediaTime(seconds: 24 * 3600), cuts: project.cuts)
            ranges = map.keptRangesHNS.map { br_kept_range(take_start_hns: $0.takeStart, take_end_hns: $0.takeEnd) }
        }
        let pip = project?.scene.camera ?? NormalizedRect.cameraPip
        let cameraPath = fileExists(camera) ? nativePath(camera) : ""
        let micPath = fileExists(mic) ? nativePath(mic) : ""
        let systemPath = fileExists(systemAudio) ? nativePath(systemAudio) : ""
        let opened = nativePath(screen).withCString { screenPointer in
            cameraPath.withCString { cameraPointer in
                micPath.withCString { micPointer in
                    systemPath.withCString { systemPointer in
                        ranges.withUnsafeBufferPointer { buffer in
                            br_player_open_take(
                                screenPointer,
                                cameraPointer,
                                micPointer,
                                systemPointer,
                                buffer.baseAddress,
                                Int32(buffer.count),
                                pip.x,
                                pip.y,
                                pip.width,
                                pip.height
                            )
                        }
                    }
                }
            }
        }
        if opened != 0 {
            print(String(cString: br_capture_last_error()))
            return
        }
        var frames = 0
        var ended: Int32 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var takeHns: Int64 = 0
        var pixels = [UInt8](repeating: 0, count: 7680 * 4320 * 4)
        var ticks = 0
        while ended == 0 && ticks < 500 {
            ticks += 1
            let code = pixels.withUnsafeMutableBufferPointer { buffer in
                br_player_tick(buffer.baseAddress, UInt32(buffer.count), &width, &height, &takeHns, &ended)
            }
            if code != 0 {
                break
            }
            frames += 1
        }
        _ = br_player_close()
        print("decoded \(frames) parallel frames from \(takeURL.path)")
    }

    /// Swift `URL.path` on Windows is often `/C:/Users/...`. MF/Win32 need `C:\Users\...`.
    static func nativePath(_ url: URL) -> String {
        var path = url.path
        #if os(Windows)
        if path.count >= 3 {
            let start = path.startIndex
            let driveColon = path.index(start, offsetBy: 2)
            if path[start] == "/", path[driveColon] == ":" {
                path.removeFirst()
            }
        }
        path = path.replacingOccurrences(of: "/", with: "\\")
        #endif
        return path
    }

    static func fileExists(_ url: URL) -> Bool {
        #if os(Windows)
        if FileManager.default.fileExists(atPath: nativePath(url)) {
            return true
        }
        #endif
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func defaultOutputRoot() -> String {
        #if os(Windows)
        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            return nativePath(movies.appendingPathComponent("BlitzRecorder", isDirectory: true))
        }
        #endif
        let home = ProcessInfo.processInfo.environment["USERPROFILE"]
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? FileManager.default.currentDirectoryPath
        return nativePath(
            URL(fileURLWithPath: home)
                .appendingPathComponent("Videos")
                .appendingPathComponent("BlitzRecorder")
        )
    }

    static func makeTakeDirectory(root: String) throws -> URL {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var directory = rootURL.appendingPathComponent(TakeFolderLayout.takeDirectoryName(), isDirectory: true)
        var suffix = 2
        while fileExists(directory) {
            directory = rootURL.appendingPathComponent(
                TakeFolderLayout.takeDirectoryName() + "-\(suffix)",
                isDirectory: true
            )
            suffix += 1
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writeTakeSidecars(takeURL: URL, microphone: Bool, systemAudio: Bool, camera: Bool) throws {
        try TakeJSON.write(TakeManifest(), to: takeURL.appendingPathComponent(TakeFolderLayout.takeManifestName))
        try TakeJSON.write(
            PortableProject.screenAndAudio(hasMicrophone: microphone, hasSystemAudio: systemAudio, hasCamera: camera),
            to: takeURL.appendingPathComponent(TakeFolderLayout.projectName)
        )
    }
}

func prepareTake(
    _ outputRoot: UnsafePointer<CChar>?,
    _ mic: Int32,
    _ systemAudio: Int32,
    _ camera: Int32,
    _ outDir: UnsafeMutablePointer<CChar>?,
    _ outDirCap: Int32,
    _ ctx: UnsafeMutableRawPointer?
) -> Int32 {
    _ = ctx
    guard let outputRoot, let outDir, outDirCap > 1 else { return 1 }
    do {
        let takeURL = try BlitzRecorderWindows.makeTakeDirectory(root: String(cString: outputRoot))
        try BlitzRecorderWindows.writeTakeSidecars(
            takeURL: takeURL,
            microphone: mic != 0,
            systemAudio: systemAudio != 0,
            camera: camera != 0
        )
        let bytes = Array(BlitzRecorderWindows.nativePath(takeURL).utf8CString)
        let count = min(Int(outDirCap), bytes.count)
        for index in 0..<count {
            outDir[index] = bytes[index]
        }
        if count == Int(outDirCap) {
            outDir[Int(outDirCap) - 1] = 0
        }
        return 0
    } catch {
        error.localizedDescription.withCString { br_set_last_error($0) }
        return 1
    }
}
