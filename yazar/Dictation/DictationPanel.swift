import AppKit

/// A borderless panel must opt into keyboard focus for recovery text selection
/// and controls. Ordinary recording never requests focus or accepts clicks.
final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
