import AppKit
import ApplicationServices
import CoreGraphics

/// Intercepts the hardware volume keys via a `CGEventTap`. Requires Accessibility
/// permission. When `onVolumeKey` returns true the key press is swallowed so the
/// system volume doesn't change as well.
final class VolumeKeyMonitor {
    /// `up` is true for volume-up, false for volume-down. Return true if the
    /// press was handled (and should be swallowed).
    var onVolumeKey: ((_ up: Bool) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let systemDefinedEventType: UInt32 = 14   // NX_SYSDEFINED
    private static let auxControlSubtype: Int16 = 8          // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    private static let soundUp = 0                           // NX_KEYTYPE_SOUND_UP
    private static let soundDown = 1                         // NX_KEYTYPE_SOUND_DOWN

    var isActive: Bool { eventTap != nil }

    /// Starts the tap. If Accessibility permission is missing, shows the system
    /// prompt and returns false.
    @discardableResult
    func enable() -> Bool {
        if eventTap != nil { return true }

        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            appLog("AppMixer: volume keys need Accessibility permission")
            return false
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefinedEventType),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<VolumeKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            appLog("AppMixer: failed to create volume-key event tap")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func disable() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    deinit { disable() }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap after a timeout or heavy input — re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == Self.auxControlSubtype
        else { return Unmanaged.passUnretained(event) }

        let keyCode = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        guard isKeyDown, keyCode == Self.soundUp || keyCode == Self.soundDown else {
            return Unmanaged.passUnretained(event)
        }

        let handled = onVolumeKey?(keyCode == Self.soundUp) ?? false
        return handled ? nil : Unmanaged.passUnretained(event)
    }
}
