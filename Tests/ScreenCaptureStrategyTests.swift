import Foundation

private func expectEqual(
    _ actual: ScreenCaptureBackend,
    _ expected: ScreenCaptureBackend,
    _ message: String
) {
    guard actual == expected else {
        fputs("FAIL: \(message)\nExpected: \(expected)\nActual: \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct ScreenCaptureStrategyTests {
    static func main() {
        expectEqual(
            ScreenCaptureService.activeBackend(
                for: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)
            ),
            .legacyScreencaptureCLI,
            "macOS 14 should keep the legacy capture backend"
        )

        expectEqual(
            ScreenCaptureService.activeBackend(
                for: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
            ),
            .legacyScreencaptureCLI,
            "macOS 15.1 should still use the legacy fallback because rect capture is unavailable"
        )

        expectEqual(
            ScreenCaptureService.activeBackend(
                for: OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)
            ),
            .nativeRegionSelection,
            "macOS 15.2 should capture natively under the app's own permission identity"
        )

        expectEqual(
            ScreenCaptureService.activeBackend(
                for: OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            .nativeRegionSelection,
            "Modern macOS should use native region selection and ScreenCaptureKit"
        )

        let rect = ScreenCaptureCoordinates.quartzRect(fromAppKit: CGRect(x: -500, y: 200, width: 300, height: 150), primaryDisplayHeight: 900)
        guard rect == CGRect(x: -500, y: 550, width: 300, height: 150) else { fatalError("global coordinate conversion") }
        let above = ScreenCaptureCoordinates.quartzRect(fromAppKit: CGRect(x: 20, y: 950, width: 100, height: 100), primaryDisplayHeight: 900)
        guard above.minY == -150 else { fatalError("display above the primary keeps negative Quartz coordinate") }
        print("ScreenCaptureStrategyTests passed")
    }
}
