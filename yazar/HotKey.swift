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

    func start() throws {
        guard tap == nil else { return }
        let eventMask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
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

private func hotKeyCallback(
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
    } else if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else { return Unmanaged.passUnretained(event) }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard !isRepeat else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { [hotKey] in hotKey.onCancel() }
    }
    return Unmanaged.passUnretained(event)
}
