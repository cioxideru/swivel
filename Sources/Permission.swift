import AppKit
import CoreGraphics

/// The two privacy permissions Swivel can need.
enum Permission {
    /// Lets the passive listener see Command + Shift. Needed for layout switching.
    case inputMonitoring
    /// Lets Swivel change scroll events. Needed for smooth scrolling and wheel reversal.
    case accessibility

    var title: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    var isGranted: Bool {
        switch self {
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: CGPreflightPostEventAccess()
        }
    }

    /// Shows the system prompt the first time; later calls do nothing visible.
    func request() {
        switch self {
        case .inputMonitoring: _ = CGRequestListenEventAccess()
        case .accessibility: _ = CGRequestPostEventAccess()
        }
    }

    func openSettings() {
        let anchor = self == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    /// Command that clears a stale entry left behind by an older build.
    var resetCommand: String {
        let service = self == .inputMonitoring ? "ListenEvent" : "Accessibility"
        return "tccutil reset \(service) \(Bundle.main.bundleIdentifier ?? "io.github.cioxideru.swivel")"
    }
}
