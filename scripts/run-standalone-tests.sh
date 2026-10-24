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
  swiftc -module-cache-path "$tmpdir/module-cache" "$@" -o "$tmpdir/$binary_name"
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
  ScreenScribe/Sources/Physics/APITransport.swift \
  ScreenScribe/Sources/Physics/RecognitionTypes.swift \
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

physics_sources=(ScreenScribe/Sources/Physics/RecognitionTypes.swift ScreenScribe/Sources/Physics/MathpixCreditEstimate.swift ScreenScribe/Sources/Physics/MathpixCreditStore.swift ScreenScribe/Sources/Physics/MathpixUsageService.swift ScreenScribe/Sources/Physics/MathpixUsageStore.swift ScreenScribe/Sources/Physics/APITransport.swift ScreenScribe/Sources/Physics/MathpixProvider.swift ScreenScribe/Sources/Physics/OpenAICompatibleVisionProvider.swift)
run_swift_test MathpixProviderTests Tests/RecognitionTestSupport.swift Tests/MathpixProviderTests.swift "${physics_sources[@]}"
run_swift_test VisionProviderTests Tests/RecognitionTestSupport.swift Tests/VisionProviderTests.swift "${physics_sources[@]}"
run_swift_test HistoryPersistenceTests Tests/RecognitionTestSupport.swift Tests/HistoryPersistenceTests.swift "${physics_sources[@]}" ScreenScribe/Sources/Physics/RecognitionHistory.swift ScreenScribe/Sources/Physics/PhysicsSettings.swift ScreenScribe/Sources/Physics/CredentialStore.swift
run_swift_test ScreenPermissionRegressionTests Tests/ScreenPermissionRegressionTests.swift ScreenScribe/Sources/Services/ScreenCapturePermissionManager.swift ScreenScribe/Sources/Services/ScreenCaptureBackend.swift -framework ScreenCaptureKit

run_swift_test MathpixUsageTests Tests/RecognitionTestSupport.swift Tests/MathpixUsageTests.swift ScreenScribe/Sources/Physics/RecognitionTypes.swift ScreenScribe/Sources/Physics/APITransport.swift ScreenScribe/Sources/Physics/MathpixUsageService.swift
run_swift_test MathpixUsageStoreTests Tests/RecognitionTestSupport.swift Tests/MathpixUsageStoreTests.swift ScreenScribe/Sources/Physics/RecognitionTypes.swift ScreenScribe/Sources/Physics/APITransport.swift ScreenScribe/Sources/Physics/MathpixUsageService.swift ScreenScribe/Sources/Physics/MathpixUsageStore.swift
run_swift_test PhysicsSettingsConcurrencyTests Tests/RecognitionTestSupport.swift Tests/PhysicsSettingsConcurrencyTests.swift "${physics_sources[@]}" ScreenScribe/Sources/Physics/PhysicsSettings.swift ScreenScribe/Sources/Physics/CredentialStore.swift

run_swift_test MathpixCreditEstimateTests Tests/RecognitionTestSupport.swift Tests/MathpixCreditEstimateTests.swift ScreenScribe/Sources/Physics/MathpixCreditEstimate.swift
run_swift_test MathpixCreditStoreTests Tests/RecognitionTestSupport.swift Tests/MathpixCreditStoreTests.swift ScreenScribe/Sources/Physics/MathpixCreditEstimate.swift ScreenScribe/Sources/Physics/MathpixCreditStore.swift
run_swift_test MathpixQuotaCadenceTests Tests/RecognitionTestSupport.swift Tests/MathpixQuotaCadenceTests.swift "${physics_sources[@]}" ScreenScribe/Sources/Physics/PhysicsSettings.swift ScreenScribe/Sources/Physics/CredentialStore.swift
