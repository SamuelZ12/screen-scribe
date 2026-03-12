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
            ScreenCaptureStrategy.preferred(
                for: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)
            ),
            .legacyScreencaptureCLI,
            "macOS 14 should keep the legacy capture backend"
        )

        expectEqual(
            ScreenCaptureStrategy.preferred(
                for: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
            ),
            .legacyScreencaptureCLI,
            "macOS 15.1 should still use the legacy fallback because rect capture is unavailable"
        )

        expectEqual(
            ScreenCaptureStrategy.preferred(
                for: OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)
            ),
            .nativeRegionSelection,
            "macOS 15.2 should prefer the native ScreenCaptureKit region backend"
        )

        expectEqual(
            ScreenCaptureStrategy.preferred(
                for: OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            .nativeRegionSelection,
            "Tahoe-era macOS releases should stay on the native ScreenCaptureKit backend"
        )

        print("ScreenCaptureStrategyTests passed")
    }
}
