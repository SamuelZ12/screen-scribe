import AppKit
import CoreGraphics
import Combine

@MainActor
final class ScreenCapturePermissionManager: ObservableObject {
    static let shared = ScreenCapturePermissionManager()
    @Published private(set) var hasPermission = false
    private let preflight: () -> Bool
    private var confirmedByCapture = false
    init(preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess) {
        self.preflight = preflight
        hasPermission = preflight()
    }
    /// Advisory only. An old false result must never block a real user-selected capture.
    @discardableResult func checkPermission() -> Bool {
        hasPermission = confirmedByCapture || preflight()
        return hasPermission
    }
    func recordSuccessfulCapture() { confirmedByCapture = true; hasPermission = true }
    func startMonitoringWithoutPrompt() async { _ = checkPermission() }
    func stopPolling() {}
    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
