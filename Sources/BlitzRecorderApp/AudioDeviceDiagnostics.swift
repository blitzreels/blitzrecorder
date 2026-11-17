import CoreAudio
import Foundation

/// Facts about the system's audio devices for the capture log. A microphone that is also the sound output can
/// stall when another capture changes how that output is tapped.
enum AudioDeviceDiagnostics {
    static func defaultOutputSummary() -> String {
        guard let device = defaultOutputDevice() else { return "default output unknown" }
        let name = string(.init(device: device, selector: kAudioObjectPropertyName)) ?? "unnamed"
        let uid = string(.init(device: device, selector: kAudioDevicePropertyDeviceUID)) ?? "no UID"
        return "default output \(name) [\(uid)]"
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private struct StringProperty {
        let device: AudioObjectID
        let selector: AudioObjectPropertySelector
    }

    private static func string(_ property: StringProperty) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: property.selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(property.device, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
