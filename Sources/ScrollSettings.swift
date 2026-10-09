import AppKit

/// Stored smooth scrolling preferences and the window that adjusts them.
/// Changes apply at once, so the feel can be tuned while scrolling.
final class ScrollSettings: NSObject {
    private struct Setting {
        let key: String
        let title: String
        let hint: String
        let range: ClosedRange<Double>
        let standard: Double
        let label: (Double) -> String
    }

    private static let speed = Setting(
        key: "ScrollSpeed", title: "Speed", hint: "How far one notch scrolls.",
        range: 30...240, standard: 90, label: { "\(Int($0)) pt per notch" })
    private static let acceleration = Setting(
        key: "ScrollAcceleration", title: "Acceleration", hint: "Extra distance when the wheel spins fast.",
        range: 1...8, standard: 4, label: { $0 < 1.05 ? "Off" : String(format: "up to %.1f×", $0) })
    private static let glideTime = Setting(
        key: "ScrollGlideTime", title: "Glide", hint: "How long the page keeps moving after the wheel stops.",
        range: 0.15...1.1, standard: 0.47, label: { "\(Int(($0 * 1000).rounded())) ms" })
    private static let all = [speed, acceleration, glideTime]

    private let defaults = UserDefaults.standard
    private let onChange: (GlideTuning) -> Void
    private var window: NSWindow?
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []

    init(onChange: @escaping (GlideTuning) -> Void) {
        self.onChange = onChange
        super.init()
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: Self.all.map { ($0.key, $0.standard) }))
    }

    var tuning: GlideTuning {
        GlideTuning(speed: defaults.double(forKey: Self.speed.key),
                    acceleration: defaults.double(forKey: Self.acceleration.key),
                    glideTime: defaults.double(forKey: Self.glideTime.key))
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let grid = NSGridView()
        grid.rowSpacing = 4
        grid.columnSpacing = 12
        for (index, setting) in Self.all.enumerated() {
            let slider = NSSlider(value: defaults.double(forKey: setting.key),
                                  minValue: setting.range.lowerBound, maxValue: setting.range.upperBound,
                                  target: self, action: #selector(slide(_:)))
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let value = NSTextField(labelWithString: setting.label(slider.doubleValue))
            value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            value.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let hint = NSTextField(labelWithString: setting.hint)
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hint.textColor = .secondaryLabelColor
            grid.addRow(with: [NSTextField(labelWithString: setting.title + ":"), slider, value])
            let hintRow = grid.addRow(with: [NSGridCell.emptyContentView, hint])
            hintRow.mergeCells(in: NSRange(location: 1, length: 2))
            hintRow.bottomPadding = 12
            sliders.append(slider)
            values.append(value)
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.yPlacement = .center

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        let resetRow = grid.addRow(with: [NSGridCell.emptyContentView, reset])
        resetRow.mergeCells(in: NSRange(location: 1, length: 2))
        resetRow.cell(at: 1).xPlacement = .trailing

        let content = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Smooth Scrolling"
        window.contentView = content
        window.isReleasedWhenClosed = false
        return window
    }

    @objc private func slide(_ slider: NSSlider) {
        let setting = Self.all[slider.tag]
        defaults.set(slider.doubleValue, forKey: setting.key)
        values[slider.tag].stringValue = setting.label(slider.doubleValue)
        onChange(tuning)
    }

    @objc private func restoreDefaults() {
        for (index, setting) in Self.all.enumerated() {
            defaults.removeObject(forKey: setting.key)
            sliders[index].doubleValue = setting.standard
            values[index].stringValue = setting.label(setting.standard)
        }
        onChange(tuning)
    }
}
