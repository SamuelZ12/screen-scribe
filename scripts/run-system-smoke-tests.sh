#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
smoke_dir=$(mktemp -d "${TMPDIR:-/tmp}/screenscribe-system-smoke.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT
swiftc -module-cache-path "$smoke_dir/module-cache" Tests/KeychainClipboardSmokeTests.swift ScreenScribe/Sources/Physics/CredentialStore.swift ScreenScribe/Sources/Physics/RecognitionTypes.swift -o "$smoke_dir/smoke"
"$smoke_dir/smoke"
