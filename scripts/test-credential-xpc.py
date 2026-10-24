#!/usr/bin/env python3
"""Exercise the frozen credential XPC service using synthetic accounts only.

Requires an already prepared local signing identity and frozen credential service.
Does not prepare identities, change trust, rebuild the service, or touch the app.
Run explicitly: python3 scripts/test-credential-xpc.py [--state-dir PATH]
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid


REPO = Path(__file__).resolve().parent.parent
SERVICE_BUNDLE = "ScreenScribeCredentialHelper.xpc"
REQUIREMENT_KEY = "ScreenScribeCredentialServiceRequirement"
SWIFT_SOURCE = r'''import Foundation

@main enum CredentialProbe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 4, args[2].hasPrefix("verification."),
              let identifier = UUID(uuidString: String(args[2].dropFirst(13))),
              "verification." + identifier.uuidString.lowercased() == args[2] else { exit(2) }
        let operation = args[1], account = args[2], report = args[3]
        DispatchQueue.global(qos: .userInitiated).async {
            var passed = false
            do {
                switch operation {
                case "saveA":
                    try CredentialStore.save("synthetic-a-no-api-credential", account: account)
                    guard try CredentialStore.read(account) == "synthetic-a-no-api-credential" else { throw ProbeFailure() }
                case "readA":
                    guard try CredentialStore.read(account) == "synthetic-a-no-api-credential" else { throw ProbeFailure() }
                case "updateDelete":
                    try CredentialStore.save("synthetic-b-no-api-credential", account: account)
                    guard try CredentialStore.read(account) == "synthetic-b-no-api-credential" else { throw ProbeFailure() }
                    try CredentialStore.delete(account)
                    guard try CredentialStore.read(account).isEmpty else { throw ProbeFailure() }
                case "missing":
                    guard try CredentialStore.read(account).isEmpty else { throw ProbeFailure() }
                case "cleanup":
                    try CredentialStore.delete(account)
                    guard try CredentialStore.read(account).isEmpty else { throw ProbeFailure() }
                case "deniedSave":
                    do {
                        try CredentialStore.save("synthetic-denied-no-api-credential", account: account)
                        throw ProbeFailure()
                    } catch is ProbeFailure { throw ProbeFailure() }
                    catch { break }
                default: throw ProbeFailure()
                }
                passed = true
            } catch { }
            let result: [String: Any] = ["passed": passed, "buildMarker": "BUILD_MARKER"]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: report), options: .atomic)
            }
            exit(passed ? 0 : 1)
        }
        RunLoop.main.run()
    }
}
struct ProbeFailure: Error { }
'''


class Failure(Exception):
    """Messages contain a fixed test phase, never subprocess output or values."""


def checked(command, phase, timeout=180):
    try:
        result = subprocess.run([str(part) for part in command], cwd=REPO,
                                capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise Failure(phase) from None
    if result.returncode:
        raise Failure(phase)
    return result


def inventory(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        raise Failure("frozen-bundle-invalid")
    files = {}
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            raise Failure("frozen-bundle-symlink")
        if path.is_file():
            files[str(path.relative_to(bundle))] = {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": stat.S_IMODE(path.stat().st_mode),
            }
    return files


def signature(app):
    result = checked(["/usr/bin/codesign", "-d", "--verbose=3", "-r-", app], "read-public-signature")
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    digest = re.search(r"^CDHash=([0-9a-fA-F]{40})$", output, re.M)
    requirement = re.search(r"^designated => (.+)$", output, re.M)
    if not digest or not requirement:
        raise Failure("read-public-signature")
    return {"cdhash": digest.group(1), "dr": requirement.group(1)}


def execute(state_dir):
    summary = {"version": 1, "allPassed": False, "onlySyntheticAccounts": True, "checks": {}}
    signing = json.loads((state_dir / "metadata.json").read_text())
    frozen_root = state_dir / "credential-xpc"
    frozen_bundle = frozen_root / SERVICE_BUNDLE
    metadata_bytes = (frozen_root / "metadata.json").read_bytes()
    metadata = json.loads(metadata_bytes)
    before = inventory(frozen_bundle)
    if not before or before != metadata["files"]:
        raise Failure("frozen-bundle-manifest-mismatch")
    architecture = platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise Failure("unsupported-architecture")
    accounts = ["verification." + str(uuid.uuid4()) for _ in range(4)]
    test_complete = False
    cleanup_ready = False
    with tempfile.TemporaryDirectory(prefix="screenscribe-xpc-synthetic-") as temporary:
        root = Path(temporary)
        app = root / "Probe.app"
        cleanup_app = root / "CleanupProbe.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        source = root / "Probe.swift"
        info_path = contents / "Info.plist"
        info_path.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": signing["identifier"], "CFBundleExecutable": "Probe",
            "CFBundleName": "Credential Synthetic Probe", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "LSUIElement": True, "LSMinimumSystemVersion": "14.0",
        }))

        def sign(bundle):
            checked([sys.executable, REPO / "scripts/local-signing/local_signing.py", "sign",
                     "--state-dir", state_dir, bundle], "sign-synthetic-app")

        def build(marker):
            source.write_text(SWIFT_SOURCE.replace("BUILD_MARKER", marker))
            checked(["/usr/bin/xcrun", "swiftc", "-O", "-swift-version", "5", "-target",
                     architecture + "-apple-macosx14.0", "-module-cache-path", root / "modules",
                     source, REPO / "ScreenScribe/Sources/Physics/CredentialStore.swift",
                     REPO / "ScreenScribe/Sources/Physics/RecognitionTypes.swift", "-o",
                     contents / "MacOS/Probe"], "compile-synthetic-app")
            checked([sys.executable, REPO / "scripts/local-signing/credential_xpc.py", "stage",
                     "--state-dir", state_dir, "--app", app], "stage-unchanged-service")
            sign(app)

        def probe(bundle, operation, account, label, record=True):
            if account not in accounts:
                raise Failure("non-synthetic-account-refused")
            report = root / (label + ".json")
            report.unlink(missing_ok=True)
            try:
                checked([bundle / "Contents/MacOS/Probe", operation, account, report], label, timeout=20)
                response = json.loads(report.read_text())
                passed = response.get("passed") is True
            except (Failure, OSError, ValueError):
                passed = False
            if record:
                summary["checks"][label] = passed
            if not passed:
                raise Failure(label)

        try:
            build("A")
            summary["identityA"] = signature(app)
            # Keep one known-good signed client for cleanup even if build B fails.
            shutil.copytree(app, cleanup_app)
            cleanup_ready = True
            probe(app, "saveA", accounts[0], "A-save-read")
            build("B")
            summary["identityB"] = signature(app)
            same_dr = summary["identityA"]["dr"] == summary["identityB"]["dr"]
            different_hash = summary["identityA"]["cdhash"] != summary["identityB"]["cdhash"]
            summary["checks"]["same-DR-different-CDHash"] = same_dr and different_hash
            if not same_dr or not different_hash:
                raise Failure("same-DR-different-CDHash")
            probe(app, "readA", accounts[0], "B-reads-A")
            probe(app, "updateDelete", accounts[0], "B-update-delete")

            wrong_client = root / "WrongDRProbe.app"
            shutil.copytree(app, wrong_client)
            checked(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
                     "--options", "runtime", "--identifier", "app.screenscribe.WrongDRProbe",
                     wrong_client], "sign-wrong-client-clone")
            probe(wrong_client, "deniedSave", accounts[1], "wrong-client-DR-rejected")
            probe(app, "missing", accounts[1], "wrong-client-created-no-item")

            wrong_policy = root / "WrongHelperPolicyProbe.app"
            shutil.copytree(app, wrong_policy)
            policy_info = wrong_policy / "Contents/Info.plist"
            info = plistlib.loads(policy_info.read_bytes())
            info[REQUIREMENT_KEY] = ('identifier "app.screenscribe.CredentialHelper" and cdhash H"'
                                     + "0" * 40 + '"')
            policy_info.write_bytes(plistlib.dumps(info))
            sign(wrong_policy)
            probe(wrong_policy, "deniedSave", accounts[2], "wrong-helper-DR-rejected")
            probe(app, "missing", accounts[2], "wrong-helper-created-no-item")

            tampered = root / "TamperedHelperProbe.app"
            shutil.copytree(app, tampered)
            helper_info = tampered / "Contents/XPCServices" / SERVICE_BUNDLE / "Contents/Info.plist"
            info = plistlib.loads(helper_info.read_bytes())
            info["CFBundleName"] = "Tampered synthetic clone"
            helper_info.write_bytes(plistlib.dumps(info))
            probe(tampered, "deniedSave", accounts[3], "tampered-helper-rejected")
            probe(app, "missing", accounts[3], "tampered-helper-created-no-item")
            test_complete = True
        except Failure as error:
            summary["failedPhase"] = str(error)
        finally:
            cleanup_ok = True
            if cleanup_ready:
                for index, account in enumerate(accounts):
                    try:
                        probe(cleanup_app, "cleanup", account, "cleanup-" + str(index), record=False)
                    except Failure:
                        cleanup_ok = False
            summary["checks"]["synthetic-items-cleaned"] = cleanup_ok
            summary["frozenBundleUnchanged"] = (
                inventory(frozen_bundle) == before and
                (frozen_root / "metadata.json").read_bytes() == metadata_bytes)
            summary["allPassed"] = test_complete and cleanup_ok and summary["frozenBundleUnchanged"]
    summary["temporaryExecutablesRemoved"] = True
    return summary


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, default=REPO / ".local-signing")
    args = parser.parse_args()
    try:
        summary = execute(args.state_dir.expanduser().resolve(strict=True))
    except (Failure, OSError, ValueError, KeyError, TypeError):
        summary = {"version": 1, "allPassed": False, "failedPhase": "setup-or-cleanup"}
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["allPassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
