import AppKit
import CoreGraphics
import QuartzCore
import os

/// Reverses and/or smooths a plain (notched) mouse wheel. Trackpads, Magic
/// Mouse and other continuous devices already scroll smoothly and pass through.
final class Wheel {
    var reverse = false
    var smooth = false {
        didSet { if !smooth { glide.stop() } }
    }
    var tuning: GlideTuning {
        get { glide.tuning }
        set { glide.tuning = newValue }
    }

    private let glide = Glide()
    private lazy var tap = EventTap(types: [.scrollWheel], listenOnly: false) { [unowned self] type, event in
        self.handle(type, event)
    }

    var isNeeded: Bool { reverse || smooth }
    var isRunning: Bool { tap.isRunning }

    @discardableResult
    func start() -> Bool { tap.start() }

    func stop() {
        tap.stop()
        glide.stop()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard type == .scrollWheel else {
            glide.stop()
            return event
        }
        // Continuous events come from trackpads and from Glide itself.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return event }
        if reverse { Self.flip(event) }
        guard smooth else { return event }
        glide.add(event)
        return nil
    }

    private static let axes: [(line: CGEventField, fixed: CGEventField, point: CGEventField, extra: [CGEventField])] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1,
         [CGEventField(rawValue: 176)!, CGEventField(rawValue: 178)!]),  // accelerated, raw
        (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
         [CGEventField(rawValue: 175)!, CGEventField(rawValue: 177)!]),
    ]

    private static func flip(_ event: CGEvent) {
        for axis in axes {
            let line = event.getIntegerValueField(axis.line)
            let fixed = event.getDoubleValueField(axis.fixed)
            let point = event.getIntegerValueField(axis.point)
            // Writing the line delta makes macOS recompute the other two, so they go last.
            event.setIntegerValueField(axis.line, value: -line)
            event.setDoubleValueField(axis.fixed, value: -fixed)
            event.setIntegerValueField(axis.point, value: -point)
            for field in axis.extra {
                event.setDoubleValueField(field, value: -event.getDoubleValueField(field))
            }
        }
    }
}

/// The parts of the glide a user can adjust.
struct GlideTuning {
    var speed = 90.0         // points per notch
    var acceleration = 4.0   // largest boost for a fast-spinning wheel, 1 turns it off
    var glideTime = 0.47     // s until the screen settles after the last notch

    /// A critically damped spring is within 1% of its target after about 6.64 / rate seconds.
    var spring: Double { 6.64 / glideTime }
}

/// Turns wheel notches into a steady glide, one scroll event per display frame.
///
/// Each notch adds `tuning.speed` points of travel (more when the wheel spins fast).
/// That travel is released evenly over a little more than the time the next
/// notch is expected, learned from the wheel's rhythm, so evenly paced notches
/// give an even speed instead of a jolt per notch. The screen then follows the
/// released target on a critically damped spring: no velocity jumps and no
/// overshoot, also when the pace changes or the wheel stops.
final class Glide: NSObject {
    var tuning = GlideTuning()
    private let boostRate = 12.0            // notches per second before travel grows
    private let slack = 1.25                // release slower than the rhythm so slowing down never runs dry
    private let firstInterval = 0.12        // s, before a rhythm is known
    private let minInterval = 0.008         // s
    private let maxInterval = 0.4           // s, a longer pause starts a new gesture
    private let intervalBlend = 0.5

    private struct Axis {
        var direction = 0.0
        var lastNotch = 0.0
        var interval = 0.0      // smoothed time between notches, 0 when unknown
        var owed = 0.0          // travel not yet released into the target
        var releaseSpeed = 0.0  // points per second
        var target = 0.0
        var position = 0.0
        var velocity = 0.0
        var carry = 0.0         // fraction of a whole point not yet posted
    }

    private var axes = [Axis(), Axis()]
    private var flags: CGEventFlags = []
    private var link: CADisplayLink?
    private var lastFrame = 0.0
    private let log = Logger(subsystem: "io.github.cioxideru.swivel", category: "glide")

    func add(_ event: CGEvent) {
        let now = CACurrentMediaTime()
        flags = event.flags
        let deltas = [event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
                      event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)]
        for index in axes.indices where deltas[index] != 0 {
            var axis = axes[index]
            let direction: Double = deltas[index] < 0 ? -1 : 1
            let gap = now - axis.lastNotch
            axis.lastNotch = now
            if direction != axis.direction {
                // Reversing stops the old motion at once.
                axis = Axis(direction: direction, lastNotch: now, position: axis.position)
                axis.target = axis.position
            } else if gap < maxInterval {
                let sample = max(gap, minInterval)
                axis.interval = axis.interval == 0 ? sample : axis.interval + (sample - axis.interval) * intervalBlend
            } else {
                axis.interval = 0
            }
            let interval = axis.interval == 0 ? firstInterval : axis.interval
            let boost = min(max(1 / (interval * boostRate), 1), tuning.acceleration)
            axis.owed += direction * tuning.speed * boost
            axis.releaseSpeed = abs(axis.owed) / (interval * slack)
            axes[index] = axis
            log.debug("notch axis=\(index) gap=\(Int(gap * 1000))ms interval=\(Int(interval * 1000))ms boost=\(boost)")
        }
        if link == nil { startLink(now) }
    }

    func stop() {
        link?.invalidate()
        link = nil
        // Keep the rhythm so slow notches that outlast the glide keep their pace.
        axes = axes.map { Axis(direction: $0.direction, lastNotch: $0.lastNotch, interval: $0.interval) }
    }

    private func startLink(_ now: Double) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = now
    }

    @objc private func frame(_ link: CADisplayLink) {
        let seconds = min(max(link.targetTimestamp - lastFrame, 0), 0.05)
        lastFrame = link.targetTimestamp
        let spring = tuning.spring
        let decay = exp(-spring * seconds)
        var steps = [0.0, 0.0]
        var whole: [Int32] = [0, 0]
        var moving = false
        for index in axes.indices {
            var axis = axes[index]
            let release = min(abs(axis.owed), axis.releaseSpeed * seconds) * (axis.owed < 0 ? -1 : 1)
            axis.owed -= release
            axis.target += release

            // Exact step of a critically damped spring, stable for any frame length.
            let offset = axis.position - axis.target
            let drift = axis.velocity + spring * offset
            let next = (offset + drift * seconds) * decay
            axis.velocity = (axis.velocity - spring * drift * seconds) * decay
            axis.position = axis.target + next
            steps[index] = next - offset

            axis.carry += steps[index]
            whole[index] = Int32(axis.carry.rounded(.towardZero))
            axis.carry -= Double(whole[index])
            moving = moving || axis.owed != 0 || abs(next) >= 0.5 || abs(axis.velocity) >= 10
            axes[index] = axis
        }

        if abs(steps[0]) >= 0.01 || abs(steps[1]) >= 0.01,
           let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: whole[0], wheel2: whole[1], wheel3: 0) {
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            // The fixed-point field counts in tenths of a point (an 8 pt event carries 0.8).
            // Writing the exact step there keeps the fraction for apps that read it.
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: steps[0] / 10)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: steps[1] / 10)
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
        if !moving { stop() }
    }
}
