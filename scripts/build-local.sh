#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
signing_state_dir="${SCREENSCRIBE_SIGNING_STATE_DIR:-$PWD/.local-signing}"
use_local_identity=false
if [[ -z "${SCREENSCRIBE_SIGNING_IDENTITY:-}" && -f "$signing_state_dir/metadata.json" ]]; then
  # Once configured, never replace a fixed identity with an ad-hoc signature.
  python3 scripts/local-signing/local_signing.py status --state-dir "$signing_state_dir"
  use_local_identity=true
fi
# Remap compiler source paths so distributable binaries do not contain a local
# checkout path. Quotes preserve paths containing spaces in Xcode's flag parser.
swift_flags='$(inherited) -enable-upcoming-feature ConciseMagicFile -file-prefix-map "'"$PWD"'=."'
xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe -configuration Release -derivedDataPath build/Local CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO OTHER_SWIFT_FLAGS="$swift_flags" build
# Remove linker debug-map paths from the shipped executable before signing.
# Keep the separate dSYM locally; never modify the immutable credential helper.
strip -S build/Local/Build/Products/Release/ScreenScribe.app/Contents/MacOS/ScreenScribe
# Pass an installed, stable signing identity to preserve macOS authorization
# across builds. The default ad-hoc identity is suitable for local use only.
if $use_local_identity; then
  # Keep the credential service's CDHash unchanged across main-app rebuilds.
  # Its NSXPC interface authenticates each new message using the fixed app DR.
  python3 scripts/local-signing/credential_xpc.py prepare --state-dir "$signing_state_dir"
  python3 scripts/local-signing/credential_xpc.py stage --state-dir "$signing_state_dir" --app build/Local/Build/Products/Release/ScreenScribe.app
  python3 scripts/local-signing/local_signing.py sign --state-dir "$signing_state_dir" build/Local/Build/Products/Release/ScreenScribe.app
else
  signing_identity="${SCREENSCRIBE_SIGNING_IDENTITY:--}"
  codesign --force --sign "$signing_identity" --timestamp=none --options runtime build/Local/Build/Products/Release/ScreenScribe.app
fi
codesign --verify --strict --verbose=2 build/Local/Build/Products/Release/ScreenScribe.app
echo "Ready: build/Local/Build/Products/Release/ScreenScribe.app"
