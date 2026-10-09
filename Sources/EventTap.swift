import CoreGraphics

/// A session-level Quartz event tap that runs on the main run loop.
/// The handler returns the event to pass it on, or nil to drop it.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let types: [CGEventType]
    private let listenOnly: Bool
    private let handler: Handler
    private var port: CFMachPort?

    init(types: [CGEventType], listenOnly: Bool, handler: @escaping Handler) {
        self.types = types
        self.listenOnly = listenOnly
        self.handler = handler
    }

    var isRunning: Bool {
        port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    /// Returns false when macOS refuses the tap, which means the permission is missing.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        stop()
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            let tap = Unmanaged<EventTap>.fromOpaque(info!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port = tap.port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return tap.handler(type, event).map { Unmanaged.passUnretained($0) }
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: listenOnly ? .listenOnly : .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        self.port = nil
    }
}
