import CoreFoundation
import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib
import Observation

enum USBCameraControlKind: String, CaseIterable, Identifiable, Sendable {
    case zoom, pan, tilt, roll
    case autoFocus, focus
    case autoExposure, exposure, gain
    case autoWhiteBalance, whiteBalance
    case brightness, contrast, saturation, sharpness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zoom: "Zoom"
        case .pan: "Pan"
        case .tilt: "Tilt"
        case .roll: "Roll"
        case .autoFocus: "Auto focus"
        case .focus: "Focus"
        case .autoExposure: "Auto exposure"
        case .exposure: "Exposure"
        case .gain: "Gain"
        case .autoWhiteBalance: "Auto white balance"
        case .whiteBalance: "Warmth"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .sharpness: "Sharpness"
        }
    }

    var isToggle: Bool { self == .autoFocus || self == .autoExposure || self == .autoWhiteBalance }
    var movesCamera: Bool { self == .pan || self == .tilt }
    var isFraming: Bool { self == .zoom || self == .pan || self == .tilt || self == .roll }

    var hiddenWhileOn: USBCameraControlKind? {
        switch self {
        case .autoFocus: .focus
        case .autoExposure: .exposure
        case .autoWhiteBalance: .whiteBalance
        default: nil
        }
    }

    func label(_ value: Int) -> String {
        switch self {
        case .zoom: String(format: "%.1f×", Double(value) / 100)
        case .pan, .tilt: "\(Int((Double(value) / 3_600).rounded()))°"
        case .roll: "\(value)°"
        case .whiteBalance: "\(value)K"
        default: "\(value)"
        }
    }
}

struct USBCameraControl: Identifiable, Equatable, Sendable {
    let kind: USBCameraControlKind
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int
    var value: Int

    var id: USBCameraControlKind { kind }

    func clamped(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

struct GimbalPosition: Equatable, Sendable {
    let pan: Int
    let tilt: Int
}

struct GimbalMove: Sendable {
    let kind: USBCameraControlKind
    let delta: Int
}

private enum GimbalChange: Sendable {
    case to(Int)
    case by(Int)

    func applied(to value: Int) -> Int {
        switch self {
        case .to(let target): target
        case .by(let delta): value + delta
        }
    }

    func adding(_ delta: Int) -> GimbalChange {
        switch self {
        case .to(let target): .to(target + delta)
        case .by(let existing): .by(existing + delta)
        }
    }
}

private struct GimbalRequest: Sendable {
    let pan: USBCameraControl
    let tilt: USBCameraControl
    let centersOrTurnsAround: Bool
    let changes: [USBCameraControlKind: GimbalChange]
}

private enum UVCRequest {
    static let setCurrent: UInt8 = 0x01
    static let getCurrent: UInt8 = 0x81
    static let getMinimum: UInt8 = 0x82
    static let getMaximum: UInt8 = 0x83
    static let getResolution: UInt8 = 0x84
    static let getDefault: UInt8 = 0x87
    static let classInterfaceIn: UInt8 = 0xA1
    static let classInterfaceOut: UInt8 = 0x21
}

private struct UVCControlSpec {
    enum Unit { case cameraTerminal, processingUnit }

    let unit: Unit
    let bit: Int
    let selector: UInt8
    let length: Int
    let kinds: [USBCameraControlKind]

    static let all: [UVCControlSpec] = [
        .init(unit: .cameraTerminal, bit: 9, selector: 0x0B, length: 2, kinds: [.zoom]),
        .init(unit: .cameraTerminal, bit: 11, selector: 0x0D, length: 8, kinds: [.pan, .tilt]),
        .init(unit: .cameraTerminal, bit: 13, selector: 0x0F, length: 2, kinds: [.roll]),
        .init(unit: .cameraTerminal, bit: 17, selector: 0x08, length: 1, kinds: [.autoFocus]),
        .init(unit: .cameraTerminal, bit: 5, selector: 0x06, length: 2, kinds: [.focus]),
        .init(unit: .cameraTerminal, bit: 1, selector: 0x02, length: 1, kinds: [.autoExposure]),
        .init(unit: .cameraTerminal, bit: 3, selector: 0x04, length: 4, kinds: [.exposure]),
        .init(unit: .processingUnit, bit: 9, selector: 0x04, length: 2, kinds: [.gain]),
        .init(unit: .processingUnit, bit: 12, selector: 0x0B, length: 1, kinds: [.autoWhiteBalance]),
        .init(unit: .processingUnit, bit: 6, selector: 0x0A, length: 2, kinds: [.whiteBalance]),
        .init(unit: .processingUnit, bit: 0, selector: 0x02, length: 2, kinds: [.brightness]),
        .init(unit: .processingUnit, bit: 1, selector: 0x03, length: 2, kinds: [.contrast]),
        .init(unit: .processingUnit, bit: 3, selector: 0x07, length: 2, kinds: [.saturation]),
        .init(unit: .processingUnit, bit: 4, selector: 0x08, length: 2, kinds: [.sharpness])
    ]

    static let panTilt = all.first { $0.kinds == [.pan, .tilt] }
}

private struct UVCLayout {
    var interfaceNumber: UInt8 = 0
    var cameraTerminalID: UInt8?
    var cameraTerminalControls = 0
    var processingUnitID: UInt8?
    var processingUnitControls = 0

    func unitID(_ unit: UVCControlSpec.Unit) -> UInt8? {
        unit == .cameraTerminal ? cameraTerminalID : processingUnitID
    }

    func supports(_ spec: UVCControlSpec) -> Bool {
        let controls = spec.unit == .cameraTerminal ? cameraTerminalControls : processingUnitControls
        return controls & (1 << spec.bit) != 0
    }

    static func parse(descriptor: UnsafeBufferPointer<UInt8>) -> UVCLayout? {
        var layout = UVCLayout()
        var offset = 0
        var isVideoControl = false
        var foundInterface = false
        while offset + 2 < descriptor.count {
            let length = Int(descriptor[offset])
            guard length > 0, offset + length <= descriptor.count else { break }
            let type = descriptor[offset + 1]
            if type == 0x04, length >= 7 {
                isVideoControl = descriptor[offset + 5] == 14 && descriptor[offset + 6] == 1
                if isVideoControl, !foundInterface {
                    layout.interfaceNumber = descriptor[offset + 2]
                    foundInterface = true
                }
            } else if type == 0x24, isVideoControl, length >= 3 {
                switch descriptor[offset + 2] {
                case 0x02 where length >= 15:
                    layout.cameraTerminalID = descriptor[offset + 3]
                    layout.cameraTerminalControls = bitmap(.init(
                        descriptor: descriptor, offset: offset + 15, size: Int(descriptor[offset + 14])
                    ))
                case 0x05 where length >= 8:
                    layout.processingUnitID = descriptor[offset + 3]
                    layout.processingUnitControls = bitmap(.init(
                        descriptor: descriptor, offset: offset + 8, size: Int(descriptor[offset + 7])
                    ))
                default:
                    break
                }
            }
            offset += length
        }
        return foundInterface ? layout : nil
    }

    private struct BitmapRequest {
        let descriptor: UnsafeBufferPointer<UInt8>
        let offset: Int
        let size: Int
    }

    private static func bitmap(_ request: BitmapRequest) -> Int {
        var value = 0
        for index in 0..<min(request.size, 4) where request.offset + index < request.descriptor.count {
            value |= Int(request.descriptor[request.offset + index]) << (8 * index)
        }
        return value
    }
}

private enum USBPlugInID {
    static let plugIn = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
    )
    static let deviceUserClient = CFUUIDGetConstantUUIDWithBytes(
        nil, 0x9D, 0xC7, 0xB7, 0x80, 0x9E, 0xC0, 0x11, 0xD4, 0xA5, 0x4F, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
    )
    static let interfaceUserClient = CFUUIDGetConstantUUIDWithBytes(
        nil, 0x2D, 0x97, 0x86, 0xC6, 0x9E, 0xF3, 0x11, 0xD4, 0xAD, 0x51, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
    )
    static let device = CFUUIDGetConstantUUIDWithBytes(
        nil, 0x5C, 0x81, 0x87, 0xD0, 0x9E, 0xF3, 0x11, 0xD4, 0x8B, 0x45, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
    )
    static let interface190 = CFUUIDGetConstantUUIDWithBytes(
        nil, 0x8F, 0xDB, 0x84, 0x55, 0x74, 0xA6, 0x11, 0xD6, 0x97, 0xB1, 0x00, 0x30, 0x65, 0xD3, 0x60, 0x8E
    )
}

private typealias USBPlugIn = UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>
private typealias USBDeviceRef = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>
private typealias USBInterfaceRef = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface190>?>

private struct UVCCaptureDeviceID {
    let locationID: Int
    let vendorID: Int
    let productID: Int

    init?(uniqueID: String) {
        guard uniqueID.hasPrefix("0x"), uniqueID.count > 10 else { return nil }
        let hex = uniqueID.dropFirst(2)
        guard let product = Int(hex.suffix(4), radix: 16),
              let vendor = Int(hex.dropLast(4).suffix(4), radix: 16),
              let location = Int(hex.dropLast(8), radix: 16) else { return nil }
        locationID = location
        vendorID = vendor
        productID = product
    }
}

private final class UVCDeviceConnection {
    private let interface: USBInterfaceRef
    private let layout: UVCLayout
    let vendorID: Int

    init?(uniqueID: String) {
        guard let id = UVCCaptureDeviceID(uniqueID: uniqueID),
              let service = Self.service(for: id) else { return nil }
        defer { IOObjectRelease(service) }
        guard let device = Self.deviceInterface(service) else { return nil }
        defer {
            _ = device.pointee?.pointee.Release(device)
        }
        var configuration: IOUSBConfigurationDescriptorPtr?
        guard device.pointee?.pointee.GetConfigurationDescriptorPtr(device, 0, &configuration) == KERN_SUCCESS,
              let configuration else { return nil }
        let bytes = UnsafeBufferPointer(
            start: UnsafeRawPointer(configuration).assumingMemoryBound(to: UInt8.self),
            count: Int(configuration.pointee.wTotalLength)
        )
        guard let layout = UVCLayout.parse(descriptor: bytes),
              let interface = Self.videoControlInterface(device) else { return nil }
        self.layout = layout
        self.interface = interface
        vendorID = id.vendorID
    }

    deinit {
        _ = interface.pointee?.pointee.Release(interface)
    }

    func readControls() -> [USBCameraControl] {
        UVCControlSpec.all.filter { layout.supports($0) }.flatMap(controls(for:))
    }

    func write(_ kind: USBCameraControlKind, values: [USBCameraControlKind: Int]) -> Bool {
        guard let spec = UVCControlSpec.all.first(where: { $0.kinds.contains(kind) }),
              let unit = layout.unitID(spec.unit) else { return false }
        var bytes = [UInt8](repeating: 0, count: spec.length)
        if kind == .autoExposure {
            let mask = read(.init(code: UVCRequest.getResolution, spec: spec, unit: unit))?.first ?? 0
            bytes[0] = values[kind] == 1 ? (mask & 8 != 0 ? 8 : 2) : 1
        } else if kind.movesCamera {
            return false
        } else {
            encode(values[kind] ?? 0, length: spec.length, into: &bytes, at: 0)
        }
        return send(.init(code: UVCRequest.setCurrent, spec: spec, unit: unit), bytes: &bytes)
    }

    func readGimbalPosition() -> GimbalPosition? {
        guard let spec = UVCControlSpec.panTilt, layout.supports(spec),
              let unit = layout.unitID(spec.unit),
              let current = read(.init(code: UVCRequest.getCurrent, spec: spec, unit: unit)) else { return nil }
        return GimbalPosition(pan: decode(current, offset: 0, length: 4), tilt: decode(current, offset: 4, length: 4))
    }

    func moveGimbal(_ request: GimbalRequest) -> GimbalPosition? {
        guard let spec = UVCControlSpec.panTilt,
              let unit = layout.unitID(spec.unit),
              let current = readGimbalPosition() else { return nil }
        var pan = current.pan
        var tilt = current.tilt
        if request.centersOrTurnsAround {
            let isCentered = abs(pan - request.pan.defaultValue) < 5 * 3_600
            pan = isCentered ? request.pan.defaultValue + 180 * 3_600 : request.pan.defaultValue
            tilt = request.tilt.defaultValue
        }
        pan = request.pan.clamped(request.changes[.pan]?.applied(to: pan) ?? pan)
        tilt = request.tilt.clamped(request.changes[.tilt]?.applied(to: tilt) ?? tilt)
        var bytes = [UInt8](repeating: 0, count: spec.length)
        encode(pan, length: 4, into: &bytes, at: 0)
        encode(tilt, length: 4, into: &bytes, at: 4)
        guard send(.init(code: UVCRequest.setCurrent, spec: spec, unit: unit), bytes: &bytes) else { return nil }
        return GimbalPosition(pan: pan, tilt: tilt)
    }

    private func controls(for spec: UVCControlSpec) -> [USBCameraControl] {
        guard let unit = layout.unitID(spec.unit) else { return [] }
        func read(_ code: UInt8) -> [UInt8]? { self.read(.init(code: code, spec: spec, unit: unit)) }
        if spec.kinds == [.autoExposure] {
            guard let current = read(UVCRequest.getCurrent)?.first else { return [] }
            let isAuto = current & 0b1010 != 0
            return [.init(kind: .autoExposure, range: 0...1, step: 1, defaultValue: 1, value: isAuto ? 1 : 0)]
        }
        if spec.length == 1 {
            guard let current = read(UVCRequest.getCurrent)?.first else { return [] }
            return [.init(kind: spec.kinds[0], range: 0...1, step: 1, defaultValue: 1, value: Int(current))]
        }
        guard let minimum = read(UVCRequest.getMinimum),
              let maximum = read(UVCRequest.getMaximum),
              let current = read(UVCRequest.getCurrent) else { return [] }
        let resolution = read(UVCRequest.getResolution)
        let fallback = read(UVCRequest.getDefault)
        let partLength = spec.length / spec.kinds.count
        return spec.kinds.enumerated().compactMap { index, kind in
            let offset = index * partLength
            let low = decode(minimum, offset: offset, length: partLength)
            let high = decode(maximum, offset: offset, length: partLength)
            guard low < high else { return nil }
            let value = decode(current, offset: offset, length: partLength)
            return USBCameraControl(
                kind: kind,
                range: low...high,
                step: max(1, resolution.map { decode($0, offset: offset, length: partLength) } ?? 1),
                defaultValue: fallback.map { decode($0, offset: offset, length: partLength) } ?? value,
                value: value
            )
        }
    }

    private struct RequestTarget {
        let code: UInt8
        let spec: UVCControlSpec
        let unit: UInt8
    }

    private func read(_ target: RequestTarget) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: target.spec.length)
        return send(target, bytes: &bytes) ? bytes : nil
    }

    private func send(_ target: RequestTarget, bytes: inout [UInt8]) -> Bool {
        let isWrite = target.code == UVCRequest.setCurrent
        let count = bytes.count
        return bytes.withUnsafeMutableBytes { buffer -> Bool in
            var request = IOUSBDevRequest(
                bmRequestType: isWrite ? UVCRequest.classInterfaceOut : UVCRequest.classInterfaceIn,
                bRequest: target.code,
                wValue: UInt16(target.spec.selector) << 8,
                wIndex: UInt16(target.unit) << 8 | UInt16(layout.interfaceNumber),
                wLength: UInt16(count),
                pData: buffer.baseAddress,
                wLenDone: 0
            )
            return interface.pointee?.pointee.ControlRequest(interface, 0, &request) == KERN_SUCCESS
        }
    }

    private func decode(_ bytes: [UInt8], offset: Int, length: Int) -> Int {
        guard offset + length <= bytes.count else { return 0 }
        var raw: UInt32 = 0
        for index in 0..<length {
            raw |= UInt32(bytes[offset + index]) << (8 * index)
        }
        return length == 2 ? Int(Int16(truncatingIfNeeded: raw)) : Int(Int32(bitPattern: raw))
    }

    private func encode(_ value: Int, length: Int, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<length {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index))
        }
    }

    private static func service(for id: UVCCaptureDeviceID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var candidate = IOIteratorNext(iterator)
        while candidate != 0 {
            if property(candidate, "idVendor") == id.vendorID,
               property(candidate, "idProduct") == id.productID,
               property(candidate, "locationID") == id.locationID {
                return candidate
            }
            IOObjectRelease(candidate)
            candidate = IOIteratorNext(iterator)
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    private static func deviceInterface(_ service: io_service_t) -> USBDeviceRef? {
        var plugIn: USBPlugIn?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(
            service, USBPlugInID.deviceUserClient, USBPlugInID.plugIn, &plugIn, &score
        ) == KERN_SUCCESS, let plugIn else { return nil }
        defer { _ = plugIn.pointee?.pointee.Release(plugIn) }
        var device: USBDeviceRef?
        let result = withUnsafeMutablePointer(to: &device) { pointer in
            pointer.withMemoryRebound(to: LPVOID?.self, capacity: 1) {
                plugIn.pointee?.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(USBPlugInID.device), $0)
            }
        }
        return result == S_OK ? device : nil
    }

    private static func videoControlInterface(_ device: USBDeviceRef) -> USBInterfaceRef? {
        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: 14,
            bInterfaceSubClass: 1,
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )
        var iterator: io_iterator_t = 0
        guard device.pointee?.pointee.CreateInterfaceIterator(device, &request, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var plugIn: USBPlugIn?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(
            service, USBPlugInID.interfaceUserClient, USBPlugInID.plugIn, &plugIn, &score
        ) == KERN_SUCCESS, let plugIn else { return nil }
        defer { _ = plugIn.pointee?.pointee.Release(plugIn) }
        var interface: USBInterfaceRef?
        let result = withUnsafeMutablePointer(to: &interface) { pointer in
            pointer.withMemoryRebound(to: LPVOID?.self, capacity: 1) {
                plugIn.pointee?.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(USBPlugInID.interface190), $0)
            }
        }
        return result == S_OK ? interface : nil
    }
}

@Observable
@MainActor
final class USBCameraControlsModel {
    private(set) var controls: [USBCameraControl] = []
    private(set) var controlError: String?
    private(set) var isApplying = false
    private(set) var isActionCamera = false
    private(set) var loadedCameraID: String?

    @ObservationIgnored private let queue = DispatchQueue(label: "recorder.usb-camera-controls")
    @ObservationIgnored nonisolated(unsafe) private var connection: UVCDeviceConnection?
    @ObservationIgnored private var pendingWrites: [USBCameraControlKind: [USBCameraControlKind: Int]] = [:]
    @ObservationIgnored private var pendingGimbal: [USBCameraControlKind: GimbalChange] = [:]
    @ObservationIgnored private var pendingCenter = false
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    private static let actionCameraVendorIDs: Set<Int> = [0x2CA3]

    var visibleControls: [USBCameraControl] {
        let hidden = Set(controls.filter { $0.kind.isToggle && $0.value == 1 }.compactMap(\.kind.hiddenWhileOn))
        return controls.filter { !hidden.contains($0.kind) }
    }

    func load(cameraID: String?) async {
        loadedCameraID = cameraID
        let result: (controls: [USBCameraControl], vendorID: Int?) = await withCheckedContinuation { continuation in
            queue.async { [self] in
                connection = cameraID.flatMap(UVCDeviceConnection.init(uniqueID:))
                continuation.resume(returning: (connection?.readControls() ?? [], connection?.vendorID))
            }
        }
        guard loadedCameraID == cameraID else { return }
        controls = result.controls
        isActionCamera = result.vendorID.map(Self.actionCameraVendorIDs.contains) ?? false
    }

    func refresh() async {
        await load(cameraID: loadedCameraID)
    }

    func setValue(_ value: Int, for kind: USBCameraControlKind) {
        guard let index = controls.firstIndex(where: { $0.kind == kind }) else { return }
        let control = controls[index]
        let snapped = control.step > 1
            ? control.range.lowerBound
                + Int((Double(value - control.range.lowerBound) / Double(control.step)).rounded()) * control.step
            : value
        controls[index].value = control.clamped(snapped)
        controlError = nil
        if kind.movesCamera {
            pendingGimbal[kind] = .to(controls[index].value)
        } else {
            pendingWrites[kind] = Dictionary(uniqueKeysWithValues: controls.map { ($0.kind, $0.value) })
        }
        startWritingIfNeeded()
    }

    func move(_ move: GimbalMove) {
        guard move.kind.movesCamera, let index = controls.firstIndex(where: { $0.kind == move.kind }) else { return }
        controls[index].value = controls[index].clamped(controls[index].value + move.delta)
        controlError = nil
        pendingGimbal[move.kind] = pendingGimbal[move.kind]?.adding(move.delta) ?? .by(move.delta)
        startWritingIfNeeded()
    }

    func centerOrTurnAround() {
        guard controls.contains(where: \.kind.movesCamera) else { return }
        controlError = nil
        pendingCenter = true
        pendingGimbal = [:]
        startWritingIfNeeded()
    }

    func refreshGimbalPosition() async {
        guard writeTask == nil, controls.contains(where: \.kind.movesCamera) else { return }
        let cameraID = loadedCameraID
        let position = await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: connection?.readGimbalPosition()) }
        }
        guard let position, writeTask == nil, loadedCameraID == cameraID else { return }
        apply(position)
    }

    private func apply(_ position: GimbalPosition) {
        for index in controls.indices {
            switch controls[index].kind {
            case .pan where controls[index].value != position.pan: controls[index].value = position.pan
            case .tilt where controls[index].value != position.tilt: controls[index].value = position.tilt
            default: break
            }
        }
    }

    private func takeGimbalRequest() -> GimbalRequest? {
        guard pendingCenter || !pendingGimbal.isEmpty,
              let pan = controls.first(where: { $0.kind == .pan }),
              let tilt = controls.first(where: { $0.kind == .tilt }) else {
            pendingCenter = false
            pendingGimbal = [:]
            return nil
        }
        defer {
            pendingCenter = false
            pendingGimbal = [:]
        }
        return GimbalRequest(pan: pan, tilt: tilt, centersOrTurnsAround: pendingCenter, changes: pendingGimbal)
    }

    func reset() {
        for control in controls where !control.kind.movesCamera {
            setValue(control.defaultValue, for: control.kind)
        }
    }

    private func startWritingIfNeeded() {
        guard writeTask == nil else { return }
        isApplying = true
        writeTask = Task { [weak self] in
            while let self {
                if let request = self.takeGimbalRequest() {
                    if let position = await self.moveGimbal(request) {
                        self.apply(position)
                    } else {
                        self.controlError = "The camera did not accept the gimbal move."
                    }
                    continue
                }
                guard let next = self.pendingWrites.popFirst() else { break }
                let wasToggle = next.key.isToggle
                let applied = await self.write(next.key, values: next.value)
                if !applied { self.controlError = "The camera did not accept the \(next.key.title.lowercased()) setting." }
                if wasToggle { await self.refresh() }
            }
            if let self {
                try? await Task.sleep(for: .milliseconds(250))
                if self.hasPendingWork == false { await self.refresh() }
                self.writeTask = nil
                self.isApplying = false
                if self.hasPendingWork { self.startWritingIfNeeded() }
            }
        }
    }

    private var hasPendingWork: Bool {
        !pendingWrites.isEmpty || !pendingGimbal.isEmpty || pendingCenter
    }

    private func moveGimbal(_ request: GimbalRequest) async -> GimbalPosition? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: connection?.moveGimbal(request))
            }
        }
    }

    private func write(_ kind: USBCameraControlKind, values: [USBCameraControlKind: Int]) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: connection?.write(kind, values: values) == true)
            }
        }
    }
}
