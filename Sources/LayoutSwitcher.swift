import Carbon
import CoreGraphics

/// Selects the next keyboard input source when Command + Shift is pressed and
/// released on its own. Any key or click in between cancels the switch, so
/// shortcuts such as Command + Shift + T keep working.
final class LayoutSwitcher {
    private static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
    private static let combo: CGEventFlags = [.maskCommand, .maskShift]

    private enum Gesture { case idle, armed, cancelled }
    private var gesture = Gesture.idle
    private lazy var tap = EventTap(
        types: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
        listenOnly: true
    ) { [unowned self] type, event in
        self.observe(type, event)
        return event
    }

    var isRunning: Bool { tap.isRunning }

    @discardableResult
    func start() -> Bool { tap.start() }

    func stop() {
        tap.stop()
        gesture = .idle
    }

    private func observe(_ type: CGEventType, _ event: CGEvent) {
        let held = type == .flagsChanged ? event.flags.intersection(Self.modifiers) : []
        if type != .flagsChanged {
            // A key or click while modifiers are down makes it a shortcut.
            if gesture == .armed { gesture = .cancelled }
        } else if held.isEmpty {
            if gesture == .armed { Self.selectNextInputSource() }
            gesture = .idle
        } else if !held.isSubset(of: Self.combo) {
            gesture = .cancelled
        } else if held == Self.combo && gesture == .idle {
            gesture = .armed
        }
    }

    static func selectNextInputSource() {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              !sources.isEmpty
        else { return }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let index = sources.firstIndex { CFEqual($0, current) } ?? -1
        TISSelectInputSource(sources[(index + 1) % sources.count])
    }
}
