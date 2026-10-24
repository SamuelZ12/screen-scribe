#!/usr/bin/env python3
"""Prepare once and stage the immutable, authenticated credential XPC service."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import stat
import sys
import tempfile

sys.dont_write_bytecode = True
import local_signing


SOURCE = Path(__file__).resolve().parent / "credential-xpc.swift"
SERVICE_NAME = "app.screenscribe.CredentialHelper"
BUNDLE_NAME = "ScreenScribeCredentialHelper.xpc"
EXECUTABLE = "ScreenScribeCredentialHelper"
INFO_KEY = "ScreenScribeCredentialServiceRequirement"


def fail(message):
    raise local_signing.SigningError(message)


def policy_for(signing):
    fingerprint = signing["certificateSHA1"].upper()
    return {
        "serviceName": SERVICE_NAME,
        "clientRequirement": f'identifier "{signing["identifier"]}" and certificate leaf = H"{fingerprint}"',
        "keychainService": "app.screenscribe.credentials.xpc.v1." + fingerprint.lower(),
    }


def policy_source(policy):
    # Public constants only. JSON strings also have valid Swift string quoting
    # for these validated ASCII identifiers and requirement expressions.
    return ("enum CredentialXPCPolicy {\n" + "".join(
        f"    static let {key} = {json.dumps(value)}\n" for key, value in sorted(policy.items())) + "}\n").encode()


def bundle_inventory(bundle):
    inventory = {}
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            fail("The immutable credential service must not contain symlinks.")
        if path.is_file():
            inventory[str(path.relative_to(bundle))] = {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": stat.S_IMODE(path.stat().st_mode),
            }
    return inventory


def paths(state):
    root = state / "credential-xpc"
    return root, root / BUNDLE_NAME, root / "metadata.json"


def verify(state, signing):
    root, bundle, metadata_path = paths(state)
    if root.is_symlink() or metadata_path.is_symlink() or bundle.is_symlink():
        fail("Credential service state must not use symlinks.")
    try:
        metadata = json.loads(metadata_path.read_text())
        if (metadata["version"] != 1 or metadata["policy"] != policy_for(signing) or
                metadata["sourceSHA256"] != local_signing.digest(SOURCE) or
                metadata["policySHA256"] != hashlib.sha256(policy_source(metadata["policy"])).hexdigest() or
                metadata["files"] != bundle_inventory(bundle) or not metadata["files"]):
            raise ValueError
        requirement = metadata["helperRequirement"]
        # This exact immutable helper is ad-hoc signed: the fixed CDHash pins its
        # code without pretending that its Keychain partition is a certificate.
        expected_prefix = f'identifier "{SERVICE_NAME}" and cdhash H"'
        if not requirement.startswith(expected_prefix) or not requirement.endswith('"'):
            raise ValueError
        cdhash = requirement[len(expected_prefix):-1]
        if len(cdhash) != 40 or any(c not in "0123456789abcdef" for c in cdhash):
            raise ValueError
    except (OSError, ValueError, TypeError, KeyError):
        fail("Existing credential helper is incomplete or changed. It will not be rebuilt or re-signed automatically; explicit credential migration is required.")
    local_signing.run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures",
                      "--test-requirement", "=" + requirement, bundle], diagnostic=True)
    return metadata


def prepare(args):
    state = local_signing.state_directory(args.state_dir)
    signing = local_signing.load_metadata(state)
    root, bundle, metadata_path = paths(state)
    if root.exists():
        verify(state, signing)
        print("Reused the immutable credential XPC service; no rebuild or re-sign occurred.")
        return
    root.mkdir(mode=0o700)
    # If interrupted or unsuccessful, leave this directory in place. Future
    # builds must refuse replacement instead of silently orphaning credentials.
    policy = policy_for(signing)
    contents = bundle / "Contents"
    macos = contents / "MacOS"
    macos.mkdir(parents=True, mode=0o700)
    info = {
        "CFBundleIdentifier": SERVICE_NAME,
        "CFBundleName": "ScreenScribe Credential Helper",
        "CFBundleExecutable": EXECUTABLE,
        "CFBundlePackageType": "XPC!",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0",
        "LSMinimumSystemVersion": "14.0",
        "XPCService": {"ServiceType": "Application", "RunLoopType": "NSRunLoop", "JoinExistingSession": True},
    }
    local_signing.private_write(contents / "Info.plist", plistlib.dumps(info))
    swiftc = local_signing.run(["/usr/bin/xcrun", "--find", "swiftc"]).decode().strip()
    sdk = local_signing.run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]).decode().strip()
    arch = platform.machine()
    if arch not in ("arm64", "x86_64"):
        fail("Unsupported local architecture for the immutable credential service.")
    with tempfile.TemporaryDirectory(prefix="screenscribe-credential-xpc-compile-") as temporary:
        temporary_path = Path(temporary)
        generated = temporary_path / "CredentialXPCPolicy.swift"
        local_signing.private_write(generated, policy_source(policy))
        local_signing.run([swiftc, "-O", "-swift-version", "5", "-sdk", sdk,
                          "-target", arch + "-apple-macosx14.0", "-module-cache-path", temporary_path / "modules",
                          SOURCE, generated, "-o", macos / EXECUTABLE], timeout=180, diagnostic=True)
    (macos / EXECUTABLE).chmod(0o700)
    local_signing.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
                      "--options", "runtime", "--identifier", SERVICE_NAME, bundle], diagnostic=True)
    # codesign's public diagnostic contains only signing metadata, not keys.
    import subprocess
    displayed = subprocess.run(["/usr/bin/codesign", "-d", "--verbose=3", str(bundle)],
                               capture_output=True, text=True, check=False)
    cdhashes = [line.split("=", 1)[1] for line in displayed.stderr.splitlines() if line.startswith("CDHash=")]
    if displayed.returncode != 0 or len(cdhashes) != 1:
        fail("The credential helper CDHash could not be determined; no replacement will be generated automatically.")
    metadata = {
        "version": 1,
        "policy": policy,
        "sourceSHA256": local_signing.digest(SOURCE),
        "policySHA256": hashlib.sha256(policy_source(policy)).hexdigest(),
        "helperRequirement": f'identifier "{SERVICE_NAME}" and cdhash H"{cdhashes[0]}"',
        "files": bundle_inventory(bundle),
    }
    local_signing.private_write(metadata_path, (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode())
    verify(state, signing)
    print("Prepared the immutable credential XPC service. No API credential or Keychain ACL was accessed.")


def stage(args):
    state = local_signing.state_directory(args.state_dir)
    signing = local_signing.load_metadata(state)
    metadata = verify(state, signing)
    _, bundle, _ = paths(state)
    app = Path(args.app).expanduser().resolve(strict=True)
    info_path = app / "Contents/Info.plist"
    if info_path.is_symlink():
        fail("The main app Info.plist must not be a symlink.")
    original = info_path.read_bytes()
    info = plistlib.loads(original)
    if info.get("CFBundleIdentifier") != signing["identifier"]:
        fail("The main app identifier does not match the credential service's fixed client policy.")
    xpc_services = app / "Contents/XPCServices"
    if xpc_services.is_symlink():
        fail("The main app XPCServices directory must not be a symlink.")
    xpc_services.mkdir(exist_ok=True)
    destination = xpc_services / BUNDLE_NAME
    if destination.is_symlink():
        fail("The embedded credential service must not be a symlink.")
    if destination.exists():
        if not destination.is_dir():
            fail("The embedded credential service path is not a directory.")
        if bundle_inventory(destination) != metadata["files"]:
            shutil.rmtree(destination)
    if not destination.exists():
        shutil.copytree(bundle, destination, copy_function=shutil.copy2)
    if bundle_inventory(destination) != metadata["files"]:
        fail("The staged credential service differs from the immutable bundle.")
    info[INFO_KEY] = metadata["helperRequirement"]
    info_format = plistlib.FMT_BINARY if original.startswith(b"bplist") else plistlib.FMT_XML
    descriptor, temporary_name = tempfile.mkstemp(prefix=".credential-info-", dir=info_path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(plistlib.dumps(info, fmt=info_format, sort_keys=True))
        os.chmod(temporary_name, stat.S_IMODE(info_path.stat().st_mode))
        os.replace(temporary_name, info_path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    print("Staged the unchanged credential XPC service and public server requirement; sign the main app next.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "stage"):
        sub = commands.add_parser(name)
        sub.add_argument("--state-dir", required=True)
        if name == "stage":
            sub.add_argument("--app", required=True)
    args = parser.parse_args()
    state = local_signing.state_directory(args.state_dir)
    with local_signing.operation_lock(state):
        {"prepare": prepare, "stage": stage}[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except (local_signing.SigningError, OSError, ValueError) as error:
        print(f"Credential service preparation stopped: {error}", file=sys.stderr)
        sys.exit(1)
