# ScreenScribe development notes

Native macOS 14+ menu bar application. Extend existing AppKit/SwiftUI/Carbon infrastructure.

- Build/sign local app: `./scripts/build-local.sh`.
- Tests without API credentials: `./scripts/run-standalone-tests.sh`.
- Optional real Keychain/clipboard smoke test in a desktop session: `./scripts/run-system-smoke-tests.sh`.
- Optional fixture LuaLaTeX/PNG checks: `./scripts/verify-fixtures.sh`.
- All UI uses one status-item NSPopover. Do not create independent result/settings/history windows. Normal startup must not present any UI.
- Never gate capture on CGPreflightScreenCaptureAccess. Native ScreenCaptureKit on macOS 15.2+ is the actual access check; no automatic authorization requests.
- Math preview is bundled KaTeX in a nonpersistent WKWebView with trust=false and a network-blocking CSP. Do not add remote assets or interpolate code into HTML/JS.
- New recognition services and SwiftUI results/history/settings live in `ScreenScribe/Sources/Physics/`.
- Add new source files to the Xcode project's source phase; it uses explicit PBX file references.
- Never store credentials in UserDefaults, source, logs, history or Secrets.plist. Use CredentialStore (Keychain).
- OpenAI-compatible secrets are scoped to the configured endpoint. No authenticated HTTP redirects.
- Only the selected screenshot goes into a recognition request. Connection tests use a synthetic formula.
- Screen Recording checks are read-only. Do not add automatic permission request popups or SCShareableContent polling. The user has already granted permission; a stale check should explain restart in the result window.
- No real OCR success claim without actual API evidence. Feynman reconstruction is experimental; no automatic execution of generated TeX.

See README.md, docs/API-VERIFICATION.md and docs/TESTING.md for workflow, limitations and validation.
