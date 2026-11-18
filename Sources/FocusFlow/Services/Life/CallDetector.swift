import AppKit
import CoreAudio
import CoreMediaIO
import Foundation

/// Coach v8 §3.2: whether the camera or a microphone is in use by any app, read from the
/// "running somewhere" device flags. No capture, no permission: FocusFlow never opens a device.
/// Polled at most every 10 s.
@MainActor
final class CallDetector {
    static let shared = CallDetector()
    private var cached: (at: Date, camera: Bool, mic: Bool)?

    func state(now: Date = Date()) -> (camera: Bool, mic: Bool) {
        if let cached, now.timeIntervalSince(cached.at) < 10 { return (cached.camera, cached.mic) }
        let value = (Self.cameraInUse(), Self.micInUse())
        cached = (now, value.0, value.1)
        return value
    }

    func inCall(frontmostDomain: String?, now: Date = Date()) -> Bool {
        let state = state(now: now)
        guard state.camera || state.mic else { return false }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return CallRule.inCall(cameraInUse: state.camera, micInUse: state.mic, runningBundleIDs: running, frontmostDomain: frontmostDomain)
    }

    // MARK: CoreAudio

    private static func micInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return false }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == noErr && value != 0
        }
    }

    // MARK: CoreMediaIO

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value) == noErr && value != 0
        }
    }
}
