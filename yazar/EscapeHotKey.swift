import Carbon.HIToolbox

/// Claims Escape while a dictation is in flight.
///
/// A registered hot key consumes the key outright and needs no Accessibility or
/// Input Monitoring grant, unlike reading key presses from an event tap. It also
/// hides Escape from every other app, so it stays registered only while there is
/// something to cancel.
final class EscapeHotKey {
    var onPress: () -> Void = {}

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func capture(_ capture: Bool) {
        guard capture else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            self.hotKey = nil
            return
        }

        guard hotKey == nil else { return }

        if handler == nil {
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
            handler = installedHandler
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
        hotKey = hotKeyRef
    }

    func stop() {
        capture(false)
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    fileprivate func pressed() {
        onPress()
    }
}

// Carbon delivers hot key events on the main thread, so the cancel runs inline.
private nonisolated func escapeHotKeyCallback(
    handler: EventHandlerCallRef?,
    event: EventRef?,
    userInfo: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userInfo else { return OSStatus(eventNotHandledErr) }
    let escapeHotKey = Unmanaged<EscapeHotKey>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { escapeHotKey.pressed() }
    return noErr
}
