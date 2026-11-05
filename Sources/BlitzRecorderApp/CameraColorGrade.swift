import Compression
import CoreGraphics
import CoreImage
import Foundation

enum VideoColorSpace {
    static let rec709 = CGColorSpace(name: CGColorSpace.coreMedia709) ?? CGColorSpaceCreateDeviceRGB()
}

struct CameraColorLUT: Codable, Equatable, Sendable {
    let name: String
    let dimension: Int
    let compressedRGB: Data
    var strength: Double
    var lookID: String?
}

enum CameraSourceLook: String, Codable, Sendable, CaseIterable {
    case standard
    case appleLog
    case djiDLog
    case sonySLog3
    case panasonicVLog

    var title: String {
        switch self {
        case .standard: "Normal video"
        case .appleLog: "Apple Log"
        case .djiDLog: "DJI D-Log"
        case .sonySLog3: "Sony S-Log3"
        case .panasonicVLog: "Panasonic V-Log"
        }
    }

    var isLog: Bool { self != .standard }
}

struct CameraColorGrade: Codable, Equatable, Sendable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var tint: Double = 0
    var sourceLook: CameraSourceLook = .standard
    var lut: CameraColorLUT?

    static let neutral = CameraColorGrade()

    var isNeutral: Bool { self == .neutral }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        sourceLook = try container.decodeIfPresent(CameraSourceLook.self, forKey: .sourceLook) ?? .standard
        lut = try container.decodeIfPresent(CameraColorLUT.self, forKey: .lut)
    }

    func cameraInput(from image: CIImage) -> CIImage {
        guard sourceLook.isLog else { return image }
        return image.colorSpace.flatMap { image.matchedFromWorkingSpace(to: $0) } ?? image
    }

    func applied(to source: CIImage) -> CIImage {
        guard !isNeutral else { return source }
        var image = source
        if sourceLook.isLog {
            image = CameraLogConversion.convert(.init(rawCodes: image, look: sourceLook))
        }
        if exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        }
        if warmth != 0 || tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6_500 + warmth * 2_500, y: tint * 60),
                "inputTargetNeutral": CIVector(x: 6_500, y: 0)
            ])
        }
        if let lut, let rgba = CameraColorLUTStore.rgba(lut) {
            let looked = CameraColorLUTStore.apply(.init(image: image, dimension: lut.dimension, rgba: rgba))
            image = lut.strength >= 1 ? looked : looked.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: image,
                kCIInputTimeKey: 1 - lut.strength
            ])
        }
        if contrast != 0 || saturation != 0 {
            image = image
                .applyingFilter("CILinearToSRGBToneCurve")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + contrast * 0.5,
                    kCIInputSaturationKey: 1 + saturation
                ])
                .applyingFilter("CISRGBToneCurveToLinear")
        }
        return image.cropped(to: source.extent)
    }
}

enum CameraColorLUTStore {
    struct ApplyRequest {
        let image: CIImage
        let dimension: Int
        let rgba: Data
    }

    private static let cache = NSCache<NSData, NSData>()

    static func apply(_ request: ApplyRequest) -> CIImage {
        request.image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": request.dimension,
            "inputCubeData": request.rgba,
            "inputColorSpace": VideoColorSpace.rec709
        ])
    }

    static func rgba(_ lut: CameraColorLUT) -> Data? {
        let key = lut.compressedRGB as NSData
        if let cached = cache.object(forKey: key) { return cached as Data }
        let count = lut.dimension * lut.dimension * lut.dimension
        guard let rgb = decompress(.init(data: lut.compressedRGB, byteCount: count * 12)) else { return nil }
        var rgba = Data(count: count * 16)
        rgba.withUnsafeMutableBytes { target in
            rgb.withUnsafeBytes { source in
                let output = target.bindMemory(to: Float32.self)
                let input = source.bindMemory(to: Float32.self)
                for index in 0..<count {
                    output[index * 4] = input[index * 3]
                    output[index * 4 + 1] = input[index * 3 + 1]
                    output[index * 4 + 2] = input[index * 3 + 2]
                    output[index * 4 + 3] = 1
                }
            }
        }
        cache.setObject(rgba as NSData, forKey: key)
        return rgba
    }

    static func compress(_ data: Data) -> Data? {
        let capacity = data.count + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_LZFSE
                )
            }
        }
        guard written > 0 else { return nil }
        output.count = written
        return output
    }

    private struct DecompressRequest {
        let data: Data
        let byteCount: Int
    }

    private static func decompress(_ request: DecompressRequest) -> Data? {
        var output = Data(count: request.byteCount)
        let written = output.withUnsafeMutableBytes { target in
            request.data.withUnsafeBytes { source in
                compression_decode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, request.byteCount,
                    source.bindMemory(to: UInt8.self).baseAddress!, request.data.count,
                    nil, COMPRESSION_LZFSE
                )
            }
        }
        return written == request.byteCount ? output : nil
    }
}

enum CameraLogConversion {
    struct Request {
        let rawCodes: CIImage
        let look: CameraSourceLook
    }

    private static let dimension = 33
    private static let cubes: [CameraSourceLook: Data] = Dictionary(
        uniqueKeysWithValues: CameraSourceLook.allCases.filter(\.isLog).map { ($0, cube(for: $0)) }
    )

    static func convert(_ request: Request) -> CIImage {
        guard let cube = cubes[request.look] else { return request.rawCodes }
        return request.rawCodes
            .applyingFilter("CIColorCube", parameters: ["inputCubeDimension": dimension, "inputCubeData": cube])
            .matchedToWorkingSpace(from: VideoColorSpace.rec709) ?? request.rawCodes
    }

    private static func cube(for look: CameraSourceLook) -> Data {
        var data = Data(count: dimension * dimension * dimension * 16)
        data.withUnsafeMutableBytes { raw in
            let cube = raw.bindMemory(to: Float32.self)
            var index = 0
            let last = Double(dimension - 1)
            for blue in 0..<dimension {
                for green in 0..<dimension {
                    for red in 0..<dimension {
                        let output = displayRGB(.init(
                            look: look,
                            red: Double(red) / last, green: Double(green) / last, blue: Double(blue) / last
                        ))
                        cube[index] = Float32(output.0)
                        cube[index + 1] = Float32(output.1)
                        cube[index + 2] = Float32(output.2)
                        cube[index + 3] = 1
                        index += 4
                    }
                }
            }
        }
        return data
    }

    private struct CodeValue {
        let look: CameraSourceLook
        let red: Double
        let green: Double
        let blue: Double
    }

    private static func displayRGB(_ code: CodeValue) -> (Double, Double, Double) {
        let scene = (
            linear(.init(look: code.look, code: code.red)),
            linear(.init(look: code.look, code: code.green)),
            linear(.init(look: code.look, code: code.blue))
        )
        let matrix = toRec709(code.look)
        return (
            encode(toneMapped(matrix[0] * scene.0 + matrix[1] * scene.1 + matrix[2] * scene.2)),
            encode(toneMapped(matrix[3] * scene.0 + matrix[4] * scene.1 + matrix[5] * scene.2)),
            encode(toneMapped(matrix[6] * scene.0 + matrix[7] * scene.1 + matrix[8] * scene.2))
        )
    }

    private static func toRec709(_ look: CameraSourceLook) -> [Double] {
        switch look {
        case .standard: [1, 0, 0, 0, 1, 0, 0, 0, 1]
        case .appleLog: [1.660491, -0.587641, -0.072850, -0.124551, 1.132900, -0.008349, -0.018151, -0.100579, 1.118730]
        case .djiDLog: [1.6746, -0.5797, -0.0949, -0.0981, 1.3340, -0.2359, -0.0410, -0.2430, 1.2840]
        case .sonySLog3: [1.626947, -0.540139, -0.086809, -0.178516, 1.417941, -0.239425, -0.044436, -0.195920, 1.240356]
        case .panasonicVLog: [1.806576, -0.695697, -0.110879, -0.170090, 1.305955, -0.135865, -0.025206, -0.154468, 1.179674]
        }
    }

    private struct LogSample {
        let look: CameraSourceLook
        let code: Double
    }

    private static func linear(_ sample: LogSample) -> Double {
        let value = sample.code
        switch sample.look {
        case .standard:
            return value
        case .appleLog:
            let r0 = -0.05641088
            let rt = 0.01
            let c = 47.28711236
            let b = 0.00964052
            let gamma = 0.08550479
            let beta = 0.69336945
            let pt = c * (rt - r0) * (rt - r0)
            if value < 0 { return r0 }
            if value < pt { return (value / c).squareRoot() + r0 }
            return pow(2, (value - beta) / gamma) - b
        case .djiDLog:
            if value <= 0.14 { return (value - 0.0929) / 6.025 }
            return (pow(10, 3.89616 * value - 2.27752) - 0.0108) / 0.9892
        case .sonySLog3:
            let cut = 171.2102946929
            let codeValue = value * 1_023
            if codeValue >= cut { return pow(10, (codeValue - 420) / 261.5) * 0.19 - 0.01 }
            return (codeValue - 95) * 0.01125 / (cut - 95)
        case .panasonicVLog:
            if value < 0.181 { return (value - 0.125) / 5.6 }
            return pow(10, (value - 0.598206) / 0.241514) - 0.00873
        }
    }

    private static func toneMapped(_ value: Double) -> Double {
        let scene = max(0, value) * 2.2
        let white = 8.0
        return scene * (1 + scene / (white * white)) / (1 + scene)
    }

    private static func encode(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped < 0.018 ? 4.5 * clamped : 1.099 * pow(clamped, 0.45) - 0.099
    }
}

struct CubeLUTError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum CubeLUTFile {
    private static let maximumStoredDimension = 33

    static func load(url: URL) throws -> CameraColorLUT {
        let text = try String(contentsOf: url, encoding: .utf8)
        var dimension: Int?
        var domainMin = (0.0, 0.0, 0.0)
        var domainMax = (1.0, 1.0, 1.0)
        var values: [Float32] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            switch parts[0] {
            case "TITLE":
                continue
            case "LUT_1D_SIZE":
                throw CubeLUTError(message: "This is a 1D LUT. Choose a 3D .cube file.")
            case "LUT_3D_SIZE":
                dimension = parts.count > 1 ? Int(parts[1]) : nil
            case "DOMAIN_MIN":
                domainMin = triple(parts) ?? domainMin
            case "DOMAIN_MAX":
                domainMax = triple(parts) ?? domainMax
            default:
                guard let color = triple(parts) else { continue }
                values.append(Float32(scaled(.init(value: color.0, low: domainMin.0, high: domainMax.0))))
                values.append(Float32(scaled(.init(value: color.1, low: domainMin.1, high: domainMax.1))))
                values.append(Float32(scaled(.init(value: color.2, low: domainMin.2, high: domainMax.2))))
            }
        }
        guard let dimension, (2...129).contains(dimension),
              values.count == dimension * dimension * dimension * 3 else {
            throw CubeLUTError(message: "This .cube file couldn't be read.")
        }
        let stored = min(dimension, maximumStoredDimension)
        let samples = stored == dimension ? values : resampled(.init(values: values, from: dimension, to: stored))
        let raw = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let compressed = CameraColorLUTStore.compress(raw) else {
            throw CubeLUTError(message: "This .cube file couldn't be read.")
        }
        return CameraColorLUT(
            name: url.deletingPathExtension().lastPathComponent,
            dimension: stored,
            compressedRGB: compressed,
            strength: 1,
            lookID: nil
        )
    }

    private static func triple(_ parts: [Substring]) -> (Double, Double, Double)? {
        guard parts.count >= 3, let first = Double(parts[parts.count - 3]),
              let second = Double(parts[parts.count - 2]), let third = Double(parts[parts.count - 1]) else {
            return nil
        }
        return (first, second, third)
    }

    private struct ScaleRequest {
        let value: Double
        let low: Double
        let high: Double
    }

    private static func scaled(_ request: ScaleRequest) -> Double {
        request.high > request.low ? (request.value - request.low) / (request.high - request.low) : request.value
    }

    private struct ResampleRequest {
        let values: [Float32]
        let from: Int
        let to: Int
    }

    private static func resampled(_ request: ResampleRequest) -> [Float32] {
        let size = request.from
        func sample(red: Int, green: Int, blue: Int, channel: Int) -> Float32 {
            request.values[(blue * size * size + green * size + red) * 3 + channel]
        }
        var output: [Float32] = []
        output.reserveCapacity(request.to * request.to * request.to * 3)
        let scale = Double(size - 1) / Double(request.to - 1)
        for blue in 0..<request.to {
            for green in 0..<request.to {
                for red in 0..<request.to {
                    let position = (Double(red) * scale, Double(green) * scale, Double(blue) * scale)
                    let low = (Int(position.0), Int(position.1), Int(position.2))
                    let high = (min(low.0 + 1, size - 1), min(low.1 + 1, size - 1), min(low.2 + 1, size - 1))
                    let t = (
                        Float32(position.0 - Double(low.0)),
                        Float32(position.1 - Double(low.1)),
                        Float32(position.2 - Double(low.2))
                    )
                    for channel in 0..<3 {
                        func mix(_ a: Float32, _ b: Float32, _ amount: Float32) -> Float32 { a + (b - a) * amount }
                        let c00 = mix(sample(red: low.0, green: low.1, blue: low.2, channel: channel),
                                      sample(red: high.0, green: low.1, blue: low.2, channel: channel), t.0)
                        let c10 = mix(sample(red: low.0, green: high.1, blue: low.2, channel: channel),
                                      sample(red: high.0, green: high.1, blue: low.2, channel: channel), t.0)
                        let c01 = mix(sample(red: low.0, green: low.1, blue: high.2, channel: channel),
                                      sample(red: high.0, green: low.1, blue: high.2, channel: channel), t.0)
                        let c11 = mix(sample(red: low.0, green: high.1, blue: high.2, channel: channel),
                                      sample(red: high.0, green: high.1, blue: high.2, channel: channel), t.0)
                        output.append(mix(mix(c00, c10, t.1), mix(c01, c11, t.1), t.2))
                    }
                }
            }
        }
        return output
    }
}

struct CameraColorLook: Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case clean = "Clean"
        case warm = "Warm and soft"
        case cinematic = "Cinematic"
    }

    let id: String
    let title: String
    let group: Group
    let strength: Double
    let tip: String

    static let all: [CameraColorLook] = [
        .init(id: "clean", title: "Clean", group: .clean, strength: 1,
              tip: "Tidy color, true skin. A safe start."),
        .init(id: "true-skin", title: "True Skin", group: .clean, strength: 1,
              tip: "Made for faces. Use it when skin looks off."),
        .init(id: "neutral", title: "Neutral", group: .clean, strength: 1,
              tip: "Fixes color without adding a style."),
        .init(id: "bright", title: "Bright", group: .clean, strength: 1,
              tip: "Lifts a dull room. Good for tutorials."),
        .init(id: "vivid", title: "Vivid", group: .clean, strength: 1,
              tip: "Richer color with natural skin."),
        .init(id: "soft", title: "Soft", group: .warm, strength: 1,
              tip: "Gentle on skin. Good for close-ups."),
        .init(id: "portrait", title: "Portrait", group: .warm, strength: 1,
              tip: "A warm film look that flatters faces."),
        .init(id: "golden", title: "Golden", group: .warm, strength: 0.8,
              tip: "Warm evening light for cold or blue rooms."),
        .init(id: "matte", title: "Matte", group: .warm, strength: 0.9,
              tip: "Faded blacks and calm color."),
        .init(id: "film-daylight", title: "Film Daylight", group: .cinematic, strength: 1,
              tip: "Film look for daylight or a bright window."),
        .init(id: "film-tungsten", title: "Film Tungsten", group: .cinematic, strength: 1,
              tip: "Film look for warm lamps indoors."),
        .init(id: "teal-orange", title: "Teal & Orange", group: .cinematic, strength: 0.6,
              tip: "Movie trailer look. Starts at 60% for natural skin."),
        .init(id: "moody", title: "Moody", group: .cinematic, strength: 0.9,
              tip: "Darker and quieter, for serious stories."),
        .init(id: "nordic", title: "Nordic", group: .cinematic, strength: 1,
              tip: "Cool and calm with muted color."),
        .init(id: "mono", title: "Black & White", group: .cinematic, strength: 1,
              tip: "No color, with full detail in skin.")
    ]

    static func look(id: String) -> CameraColorLook? { all.first { $0.id == id } }

    func applying(to grade: CameraColorGrade) -> CameraColorGrade? {
        guard let loaded = CameraColorLookLibrary.shared.lut(for: self) else { return nil }
        var result = grade
        result.lut = loaded
        return result
    }
}

final class CameraColorLookLibrary: @unchecked Sendable {
    static let shared = CameraColorLookLibrary()
    private let lock = NSLock()
    private var loaded: [String: CameraColorLUT] = [:]

    func lut(for look: CameraColorLook) -> CameraColorLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = loaded[look.id] { return cached }
        guard let url = Bundle.main.url(forResource: look.id, withExtension: "cube", subdirectory: "ColorLooks"),
              var lut = try? CubeLUTFile.load(url: url) else { return nil }
        lut.lookID = look.id
        lut.strength = look.strength
        loaded[look.id] = lut
        return lut
    }

    func preload() async {
        await Task.detached(priority: .userInitiated) {
            for look in CameraColorLook.all { _ = self.lut(for: look) }
        }.value
    }
}
