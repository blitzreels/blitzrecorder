import XCTest
@testable import BlitzRecorderCore

@discardableResult
func assertCodableRoundTrip<Value: Codable & Equatable>(
    _ value: Value,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Value {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    XCTAssertEqual(decoded, value, file: file, line: line)
    return decoded
}

func decodeJSON<Value: Decodable>(_ json: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(json.utf8))
}

extension RemoteCameraCapabilities {
    static func fixture(_ configure: (inout RemoteCameraCapabilities) -> Void = { _ in }) -> RemoteCameraCapabilities {
        var capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide],
            supportedFormats: [],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
        configure(&capabilities)
        return capabilities
    }

    mutating func enableCinematicVideo() {
        supportsCinematicVideo = true
        minimumCinematicAperture = 1.4
        maximumCinematicAperture = 16
        defaultCinematicAperture = 2.8
    }
}
