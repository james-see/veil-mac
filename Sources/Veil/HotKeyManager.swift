import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon RegisterEventHotKey (works without Accessibility permission).
final class HotKeyManager {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { mgr.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }

    /// keyCode: kVK_* ; modifiers: cmdKey | optionKey | controlKey | shiftKey
    func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x5645_494C) /* 'VEIL' */, id: id)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref); handlers[id] = action
    }

    deinit {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
