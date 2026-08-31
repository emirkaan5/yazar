import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum HotKeyError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        "Yazar could not start its event tap. Grant Accessibility permission, then relaunch."
    }
}

final class HotKey {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var wasDown = false
    private var escapeHotKey: EventHotKeyRef?
    private var escapeHandler: EventHandlerRef?

    func start() throws {
        guard tap == nil else { return }
        let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotKeyError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        captureEscape(false)
        if let escapeHandler { RemoveEventHandler(escapeHandler) }
        escapeHandler = nil
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
        wasDown = false
    }

    /// Claims Escape while a dictation is in flight. A registered hot key
    /// consumes the key outright and needs no Accessibility or Input Monitoring
    /// grant, unlike reading key presses from the event tap. It also hides
    /// Escape from every other app, so it stays registered only while there is
    /// something to cancel.
    func captureEscape(_ capture: Bool) {
        guard capture else {
            if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
            escapeHotKey = nil
            return
        }

        guard escapeHotKey == nil else { return }

        if escapeHandler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            var installedHandler: EventHandlerRef?
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                escapeHotKeyCallback,
                1,
                &spec,
                Unmanaged.passUnretained(self).toOpaque(),
                &installedHandler
            )
            guard status == noErr, let installedHandler else {
                NSLog("Yazar could not install its Escape handler (OSStatus %d)", status)
                return
            }
            escapeHandler = installedHandler
        }

        var hotKeyRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x59_41_5A_52), id: 1)
        // Fails with eventHotKeyExistsErr if another app already owns a bare
        // Escape. Nothing to recover to, but silence would look like a dead key.
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            NSLog("Yazar could not register Escape to cancel (OSStatus %d)", status)
            return
        }
        escapeHotKey = hotKeyRef
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handleFlags(_ flags: CGEventFlags) {
        let isDown = flags.contains(.maskSecondaryFn)
        guard isDown != wasDown else { return }
        wasDown = isDown
        if isDown {
            onPress()
        } else {
            onRelease()
        }
    }
}

private nonisolated func hotKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { [hotKey] in hotKey.reenable() }
    } else if type == .flagsChanged {
        let flags = event.flags
        DispatchQueue.main.async { [hotKey] in hotKey.handleFlags(flags) }
    }
    return Unmanaged.passUnretained(event)
}


// Carbon delivers hot key events on the main thread, so the cancel runs inline.
private nonisolated func escapeHotKeyCallback(
    handler: EventHandlerCallRef?,
    event: EventRef?,
    userInfo: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userInfo else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { hotKey.onCancel() }
    return noErr
}
