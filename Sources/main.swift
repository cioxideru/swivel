import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Key {
        static let layout = "SwitchLayout"
        static let smooth = "SmoothScrolling"
        static let reverse = "ReverseWheel"
        static func requested(_ permission: Permission) -> String { "Requested\(permission.title)" }
    }

    private let defaults = UserDefaults.standard
    private let layout = LayoutSwitcher()
    private let wheel = Wheel()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Key.layout: true])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "StatusIcon")
            ?? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Swivel")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        menu.delegate = self
        statusItem.menu = menu
        apply()
        if defaults.bool(forKey: Key.layout) && !layout.isRunning { request(.inputMonitoring) }
        if wheel.isNeeded && !wheel.isRunning { request(.accessibility) }
    }

    // MARK: State

    /// Starts or stops each part to match the toggles. Taps are attempted
    /// directly because their creation is the only reliable permission check.
    private func apply() {
        if defaults.bool(forKey: Key.layout) { layout.start() } else { layout.stop() }
        wheel.reverse = defaults.bool(forKey: Key.reverse)
        wheel.smooth = defaults.bool(forKey: Key.smooth)
        if wheel.isNeeded { wheel.start() } else { wheel.stop() }

        let healthy = missing.isEmpty
        statusItem.button?.appearsDisabled = !healthy
        statusItem.button?.toolTip = healthy ? "Swivel" : "Swivel needs permission — open the menu"
        if healthy {
            retryTimer?.invalidate()
            retryTimer = nil
        } else if retryTimer == nil {
            // Picks up a permission as soon as it is granted in System Settings.
            retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.apply() }
        }
    }

    /// Permissions that an enabled feature needs but cannot use yet.
    private var missing: [Permission] {
        var result: [Permission] = []
        if defaults.bool(forKey: Key.layout) && !layout.isRunning { result.append(.inputMonitoring) }
        if wheel.isNeeded && !wheel.isRunning { result.append(.accessibility) }
        return result
    }

    private func request(_ permission: Permission) {
        permission.request()
        defaults.set(true, forKey: Key.requested(permission))
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        apply()
        menu.removeAllItems()
        menu.addItem(toggle("Switch Layout with ⌘⇧", Key.layout))
        menu.addItem(toggle("Smooth Scrolling", Key.smooth))
        menu.addItem(toggle("Reverse Mouse Wheel", Key.reverse))

        let needed = (defaults.bool(forKey: Key.layout) ? [Permission.inputMonitoring] : [])
            + (wheel.isNeeded ? [Permission.accessibility] : [])
        if !needed.isEmpty {
            menu.addItem(.separator())
            for permission in needed {
                let ok = !missing.contains(permission)
                let item = NSMenuItem(title: "\(permission.title): \(ok ? "Allowed" : "Allow…")",
                                      action: ok ? nil : #selector(fixPermission(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = permission
                item.image = NSImage(systemSymbolName: ok ? "checkmark.circle" : "exclamationmark.triangle",
                                     accessibilityDescription: nil)
                item.isEnabled = !ok
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("About Swivel", #selector(showAbout)))
        menu.addItem(action("Quit Swivel", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func toggle(_ title: String, _ key: String) -> NSMenuItem {
        let item = action(title, #selector(toggleFeature(_:)))
        item.representedObject = key
        item.state = defaults.bool(forKey: key) ? .on : .off
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        apply()
        for permission in missing where !defaults.bool(forKey: Key.requested(permission)) {
            request(permission)
        }
    }

    @objc private func fixPermission(_ sender: NSMenuItem) {
        guard let permission = sender.representedObject as? Permission else { return }
        if !defaults.bool(forKey: Key.requested(permission)) {
            request(permission)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow \(permission.title) for Swivel"
        alert.informativeText = """
            Switch Swivel on in System Settings → Privacy & Security → \(permission.title). \
            Swivel notices the change by itself within a couple of seconds.

            Already switched on? Then that entry belongs to an older copy of the app. \
            Remove Swivel from the list with the − button and add it again, or run this in Terminal:

            \(permission.resetCommand)
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            permission.openSettings()
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(permission.resetCommand, forType: .string)
        default:
            break
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(
            string: """
                Command + Shift switches keyboard layouts.
                Plain mouse wheels scroll smoothly, in either direction.

                Public domain. Take it, change it, sell it — no credit needed.

                """,
            attributes: body)
        var link = body
        link[.link] = URL(string: "https://github.com/cioxideru/swivel")!
        credits.append(NSAttributedString(string: "github.com/cioxideru/swivel", attributes: link))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
