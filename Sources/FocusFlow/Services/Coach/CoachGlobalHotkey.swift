import Carbon.HIToolbox
import Foundation

/// ⌃⌥Space starts a starter block from anywhere (rescue loop design §3.4).
///
/// Uses Carbon `RegisterEventHotKey`, which needs no Accessibility permission. The handler is
/// installed once on the application event target; registering and unregistering only toggles
/// the hot key itself.
@MainActor
final class CoachGlobalHotkey: CoachHotkeyRegistering {
    static let shared = CoachGlobalHotkey()

    /// 'FFHK'
    nonisolated static let signature: OSType = 0x4646_484B
    nonisolated static let keyCode = UInt32(kVK_Space)
    nonisolated static let modifiers = UInt32(controlKey | optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: (() -> Void)?

    var isRegistered: Bool { hotKeyRef != nil }

    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr, hotKeyID.signature == CoachGlobalHotkey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { CoachGlobalHotkey.shared.onPress?() }
                }
                return noErr
            }, 1, &spec, nil, &handlerRef)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(Self.keyCode, Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
