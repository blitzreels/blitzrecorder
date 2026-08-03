import AVFoundation
import CoreMediaIO
import Foundation

private struct LocalCameraPropertyRequest {
    let objectID: CMIOObjectID
    let selector: CMIOObjectPropertySelector
}

enum LocalCameraUsage {
    static func isRunningSomewhere(_ device: AVCaptureDevice) -> Bool {
        deviceSnapshots().contains { snapshot in
            snapshot.uniqueID == device.uniqueID && snapshot.isRunningSomewhere
        }
    }

    private static func deviceSnapshots() -> [DeviceSnapshot] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = propertyAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }

        var devices = [CMIOObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<CMIOObjectID>.size
        )
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buffer in
            CMIOObjectGetPropertyData(
                system,
                &address,
                0,
                nil,
                size,
                &used,
                buffer.baseAddress!
            )
        }
        guard status == noErr else { return [] }

        return devices.compactMap { device in
            guard let uniqueID = stringProperty(.init(
                objectID: device,
                selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)
            )) else { return nil }
            return DeviceSnapshot(
                uniqueID: uniqueID,
                isRunningSomewhere: uint32Property(.init(
                    objectID: device,
                    selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
                )) != 0
            )
        }
    }

    private static func stringProperty(_ request: LocalCameraPropertyRequest) -> String? {
        var address = propertyAddress(request.selector)
        var value: CFString?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            CMIOObjectGetPropertyData(
                request.objectID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<CFString?>.size),
                &used,
                pointer
            )
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func uint32Property(_ request: LocalCameraPropertyRequest) -> UInt32 {
        var address = propertyAddress(request.selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            request.objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &used,
            &value
        )
        return status == noErr ? value : 0
    }

    private static func propertyAddress(
        _ selector: CMIOObjectPropertySelector
    ) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private struct DeviceSnapshot {
        let uniqueID: String
        let isRunningSomewhere: Bool
    }
}
