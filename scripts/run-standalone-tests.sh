#!/bin/zsh

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/screenscribe-standalone-tests.XXXXXX")

cleanup() {
  rm -rf "$tmpdir"
}

trap cleanup EXIT

run_swift_test() {
  local binary_name=$1
  shift

  echo "Running $binary_name"
  swiftc "$@" -o "$tmpdir/$binary_name"
  "$tmpdir/$binary_name"
}

cd "$repo_root"

run_swift_test \
  GeminiModelCatalogTests \
  Tests/GeminiModelCatalogTests.swift \
  ScreenScribe/Sources/Config.swift

run_swift_test \
  GeminiServiceRequestTests \
  Tests/GeminiServiceRequestTests.swift \
  ScreenScribe/Sources/Services/GeminiService.swift \
  ScreenScribe/Sources/Config.swift

run_swift_test \
  ScreenCaptureCLIArgumentsTests \
  Tests/ScreenCaptureCLIArgumentsTests.swift \
  ScreenScribe/Sources/Services/ScreenCaptureBackend.swift \
  ScreenScribe/Sources/Logger.swift \
  -framework AppKit \
  -framework ScreenCaptureKit

run_swift_test \
  ScreenCaptureStrategyTests \
  Tests/ScreenCaptureStrategyTests.swift \
  ScreenScribe/Sources/Services/ScreenCaptureBackend.swift \
  ScreenScribe/Sources/Logger.swift \
  -framework AppKit \
  -framework ScreenCaptureKit

run_swift_test \
  ScreenRegionSelectionTeardownTests \
  Tests/ScreenRegionSelectionTeardownTests.swift \
  ScreenScribe/Sources/Services/ScreenCaptureBackend.swift \
  ScreenScribe/Sources/Logger.swift \
  -framework AppKit \
  -framework ScreenCaptureKit
