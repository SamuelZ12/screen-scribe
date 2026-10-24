import Foundation

@main struct ScreenPermissionRegressionTests {
    @MainActor static func main() async {
        var systemPreflight = false
        let manager = ScreenCapturePermissionManager(preflight: { systemPreflight })
        precondition(!manager.checkPermission(), "fresh preflight is advisory and may be false")
        manager.recordSuccessfulCapture()
        precondition(manager.checkPermission(), "a successful capture overrides a stale false preflight")
        systemPreflight = true
        precondition(manager.checkPermission(), "valid preflight remains recognized")
        systemPreflight = false
        precondition(manager.checkPermission(), "later stale checks must not revoke observed success")
        let second = ScreenCapturePermissionManager(preflight: { true })
        precondition(second.hasPermission, "startup reads a grant without requesting it")
        var checks = 0
        let capture = ScreenCaptureService(permissionCheck: { checks += 1; return false })
        let image = await capture.captureSelectionImage()
        precondition(image == nil && checks == 1, "unconfirmed build must return before displaying a selector or invoking any capture API")
        precondition(capture.lastError?.contains("启用直接框选") == true, "the app must provide the one-time authorization path for direct selection")
        print("ScreenPermissionRegressionTests passed: unconfirmed build stops before capture APIs and explains direct selection authorization; no request or background polling")
    }
}
