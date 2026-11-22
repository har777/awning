import Carbon
import Foundation

struct HotKeyPreset {
    let id: String
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyPreset] = [
        HotKeyPreset(id: "option-space", title: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotKeyPreset(id: "control-grave", title: "⌃ `", keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey)),
        HotKeyPreset(id: "option-grave", title: "⌥ `", keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey)),
        HotKeyPreset(id: "shift-cmd-space", title: "⇧⌘ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        HotKeyPreset(id: "option-cmd-n", title: "⌥⌘ N", keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey)),
    ]

    static func preset(id: String) -> HotKeyPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Global hotkey via Carbon `RegisterEventHotKey`: works system-wide without
/// Accessibility / Input Monitoring permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private static let signature: OSType = 0x514E_5445 // 'QNTE'

    var onPress: (() -> Void)?
    private(set) var current: HotKeyPreset?
    private(set) var isRegistered = false
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    /// Returns false if the combination is taken by another app or the system.
    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        installHandlerIfNeeded()
        unregister()
        current = preset
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        isRegistered = status == noErr && newRef != nil
        ref = isRegistered ? newRef : nil
        return isRegistered
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        isRegistered = false
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, userData in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers this on the main thread: call straight through, no extra hop.
            Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().onPress?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
