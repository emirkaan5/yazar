import CoreGraphics
import Foundation

enum HotKeyError: LocalizedError, Hashable {
    case eventTapUnavailable

    var errorDescription: String? {
        "Yazar could not start its event tap. Grant Accessibility permission, then relaunch."
    }
}

/// Watches the global modifier stream and reports which modifiers are held.
///
/// It does not know which combination means "dictate": that depends on a
/// setting, so the match lives with the state machine that owns one.
final class HotKey {
    var onModifiersChanged: (Set<TriggerModifier>) -> Void = { _ in }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() throws(HotKeyError) {
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
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handleFlags(_ flags: CGEventFlags) {
        onModifiersChanged(TriggerModifier.held(inRawFlags: flags.rawValue))
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

