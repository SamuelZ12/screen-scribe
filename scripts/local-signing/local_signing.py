#!/usr/bin/env python3
"""Explicit, scoped local code signing. No automatic trust or ad-hoc fallback."""

import argparse
import datetime
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile


SCRIPT_DIR = Path(__file__).resolve().parent
REPO = SCRIPT_DIR.parent.parent
SOURCE = SCRIPT_DIR / "security-helper.swift"
SERVICE = "app.screenscribe.local-signing.keychain-password.v1"
DEFAULT_IDENTIFIER = "app.samuelz12.screenscribe-dev"


class SigningError(Exception):
    pass


def run(argv, *, data=None, timeout=60, diagnostic=False):
    """Secrets, when needed, are passed only as stdin bytes, never arguments."""
    try:
        result = subprocess.run(
            [str(x) for x in argv], input=data, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, stdin=subprocess.DEVNULL if data is None else None,
            timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise SigningError(f"{Path(str(argv[0])).name} timed out; no access controls were relaxed.") from None
    if result.returncode:
        message = f"{Path(str(argv[0])).name} failed (exit {result.returncode})."
        if diagnostic:
            # Only our helper's fixed, sanitized messages are allowed here.
            message += " " + result.stderr.decode("utf-8", errors="replace").strip()
        raise SigningError(message)
    return result.stdout


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest().upper()


def state_directory(value, *, create=False):
    raw = Path(value).expanduser()
    if not raw.is_absolute():
        raw = Path.cwd() / raw
    # Resolve without accepting a symlink as a location for signing material.
    for ancestor in (raw, *raw.parents):
        if ancestor.is_symlink():
            raise SigningError("The signing directory and its parents must not be symlinks.")
    target = raw.resolve()
    try:
        target.relative_to(REPO)
    except ValueError:
        raise SigningError("Choose an explicitly gitignored directory inside this checkout, for example .local-signing.") from None
    ignored = subprocess.run(
        ["git", "-C", str(REPO), "check-ignore", "--quiet", "--", str(target / "signing-material")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if ignored.returncode != 0:
        raise SigningError("The requested signing directory is not ignored by Git; preparation was refused.")
    if create:
        target.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not target.is_dir():
        raise SigningError("The signing directory does not exist; run prepare explicitly first.")
    info = target.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise SigningError("The signing directory must belong to the current user and have mode 0700.")
    return target


def private_write(path, contents):
    # These files are public metadata/certificates, but still avoid overwrite and
    # symlink races in the private state directory.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(contents)


def write_metadata(directory, metadata):
    temp = directory / "metadata.json.new"
    private_write(temp, (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode())
    os.replace(temp, directory / "metadata.json")


def account_for(directory):
    return hashlib.sha256(str(directory).encode()).hexdigest()


def helper(directory, metadata, operation, **fields):
    request = {
        "operation": operation,
        "keychainPath": metadata["keychainPath"],
        "certificateSHA1": metadata["certificateSHA1"],
        "service": SERVICE,
        "account": account_for(directory),
        **fields,
    }
    output = run([directory / "security-helper"],
                 data=json.dumps(request).encode(), timeout=30, diagnostic=True)
    try:
        response = json.loads(output)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise SigningError("The signing helper returned an invalid response.") from None
    if response.get("status") != "ok":
        raise SigningError("The signing helper did not confirm success.")
    return response


@contextlib.contextmanager
def operation_lock(directory):
    descriptor = os.open(directory / "operation.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


@contextlib.contextmanager
def discoverable_keychain(keychain_path):
    # On this macOS version codesign --keychain filters the identities it can
    # discover through the search list. A dedicated KC outside that list yielded
    # "no identity found" even with a valid scoped trust setting. Register it
    # only for the short signing operation, then restore the user's list.
    def read_list():
        return shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"]).decode())
    original = read_list()
    canonical = str(Path(keychain_path).resolve())
    if any(str(Path(item).resolve()) == canonical for item in original):
        yield
        return
    expected = [keychain_path, *original]
    run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *expected])
    try:
        yield
    finally:
        current = read_list()
        # Preserve independent edits made while signing; otherwise restore the
        # exact previous ordering. The default Keychain is never changed.
        restored = original if [str(Path(p).resolve()) for p in current] == [str(Path(p).resolve()) for p in expected] else [p for p in current if str(Path(p).resolve()) != canonical]
        run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *restored])
        if [str(Path(p).resolve()) for p in read_list()] != [str(Path(p).resolve()) for p in restored]:
            raise SigningError("The original Keychain search list could not be restored; stop and inspect settings.")


def load_metadata(directory):
    path = directory / "metadata.json"
    if path.is_symlink() or not path.is_file():
        raise SigningError("No existing local signing configuration. Run prepare explicitly; identities are never generated by sign.")
    try:
        metadata = json.loads(path.read_text())
        fingerprint = metadata["certificateSHA1"]
        if (metadata["version"] != 1 or not metadata["prepared"] or
                len(fingerprint) != 40 or any(c not in "0123456789ABCDEF" for c in fingerprint)):
            raise ValueError
        identifier = metadata["identifier"]
        if not identifier or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" for c in identifier):
            raise ValueError
        for name in ("keychainPath", "certificatePath", "helperPath"):
            material = Path(metadata[name])
            if material.parent != directory or material.is_symlink() or not material.is_file():
                raise ValueError
        if Path(metadata["helperPath"]) != directory / "security-helper":
            raise ValueError
        if digest(Path(metadata["certificatePath"]), "sha1") != fingerprint:
            raise ValueError
        if digest(SOURCE) != metadata["helperSourceSHA256"]:
            raise SigningError("The Security helper source changed. Refusing to rebuild it and invalidate its Keychain ACL automatically; preserve this identity and explicitly migrate the helper.")
        if digest(Path(metadata["helperPath"])) != metadata["helperSHA256"]:
            raise SigningError("The fixed Security helper changed; signing was refused.")
    except (KeyError, TypeError, ValueError, OSError):
        raise SigningError("The existing signing configuration is incomplete or inconsistent. It will not be replaced or regenerated automatically.") from None
    return metadata


def prepare(args):
    directory = state_directory(args.state_dir, create=True)
    if (directory / "metadata.json").exists():
        metadata = load_metadata(directory)
        if metadata["identifier"] != args.identifier:
            raise SigningError("Existing identity has a different identifier; it will not be replaced.")
        helper(directory, metadata, "unlock")
        helper(directory, metadata, "lock")
        print(f"Reused the existing identity {metadata['certificateSHA1']}. No certificate was regenerated.")
        return
    if any(directory.iterdir()):
        raise SigningError("The requested directory is not empty. Refusing to overwrite or regenerate signing material.")

    swiftc = run(["/usr/bin/xcrun", "--find", "swiftc"]).decode().strip()
    sdk = run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]).decode().strip()
    binary = directory / "security-helper"
    # The helper is compiled exactly once; its signature is its Keychain ACL identity.
    with tempfile.TemporaryDirectory(prefix="screenscribe-signing-compiler-") as cache:
        run([swiftc, "-O", "-sdk", sdk, "-module-cache-path", cache, str(SOURCE), "-o", str(binary)], timeout=180, diagnostic=True)
    binary.chmod(0o700)
    openssl = shutil.which("openssl")
    if not openssl:
        raise SigningError("OpenSSL is required for explicit local identity preparation.")

    metadata = {
        "version": 1, "prepared": False,
        "identifier": args.identifier,
        "keychainPath": str(directory / "signing.keychain"),
        "certificatePath": str(directory / "certificate.der"),
        "helperPath": str(binary),
        "helperSourceSHA256": digest(SOURCE),
        "helperSHA256": digest(binary),
        "createdUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    # Passwords and private keys exist only in memory/stdin and this mode-0700
    # temporary directory. Never record passwords in metadata or a sidecar file.
    password = secrets.token_urlsafe(48)
    try:
        with tempfile.TemporaryDirectory(prefix=".prepare-", dir=directory) as temp_value:
            temp = Path(temp_value)
            key = temp / "private-key.pem"
            certificate = temp / "certificate.pem"
            pkcs12 = temp / "identity.p12"
            config = temp / "certificate.cnf"
            private_write(config, b"[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n[dn]\nCN=ScreenScribe Local Development\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n")
            run([openssl, "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes",
                 "-sha256", "-days", "3650", "-config", config,
                 "-keyout", key, "-out", certificate], timeout=90)
            key.chmod(0o600)
            run([openssl, "x509", "-in", certificate, "-outform", "DER",
                 "-out", metadata["certificatePath"]])
            Path(metadata["certificatePath"]).chmod(0o600)
            metadata["certificateSHA1"] = digest(Path(metadata["certificatePath"]), "sha1")
            metadata["certificateSHA256"] = digest(Path(metadata["certificatePath"]))
            # Legacy PBE is chosen solely for the transient PKCS12 import format;
            # the signing key itself is RSA-3072 and its certificate uses SHA-256.
            run([openssl, "pkcs12", "-export", "-inkey", key, "-in", certificate,
                 "-out", pkcs12, "-keypbe", "PBE-SHA1-3DES",
                 "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1", "-passout", "stdin"],
                data=(password + "\n").encode())
            pkcs12.chmod(0o600)
            # Write a public checkpoint before importing. If interrupted, refuse
            # automatic regeneration and preserve the identity for inspection.
            write_metadata(directory, metadata)
            response = helper(directory, metadata, "prepare", password=password, pkcs12Path=str(pkcs12))
            metadata["keychainPath"] = response["keychainPath"]
            metadata["prepared"] = True
            write_metadata(directory, metadata)
    finally:
        password = None
    print(f"Prepared identity {metadata['certificateSHA1']} in {directory}.")
    print("No trust setting or screen-recording authorization was changed.")
    print("activate-trust is a separate explicit command; preparation alone does not enable signing.")


def activate_trust(args):
    directory = state_directory(args.state_dir)
    metadata = load_metadata(directory)
    print("This explicit command authorizes only this certificate for the current user's codeSign policy,")
    print("constrained to /usr/bin/codesign. macOS may ask you to authenticate this trust change.")
    print(f"Certificate SHA-256: {metadata['certificateSHA256']}", flush=True)
    # Do not use -d, System.keychain, SSL/basic policies, or general Always Trust.
    # This is the only command that intentionally permits a system auth dialog.
    helper(directory, metadata, "unlock")
    try:
        result = subprocess.run([
            "/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign",
            "-a", "/usr/bin/codesign", "-k", metadata["keychainPath"], metadata["certificatePath"]],
            stdin=subprocess.DEVNULL, check=False)
        if result.returncode:
            raise SigningError("The scoped user trust change was not completed; no signing fallback will be used.")
    finally:
        helper(directory, metadata, "lock")
    print("Scoped trust activation completed. No screen-recording authorization was changed.")


def sign(args):
    directory = state_directory(args.state_dir)
    metadata = load_metadata(directory)
    identifier = args.identifier or metadata["identifier"]
    if identifier != metadata["identifier"]:
        raise SigningError("The signing identifier must match the prepared identity.")
    app = Path(args.app).expanduser().resolve(strict=True)
    fingerprint = metadata["certificateSHA1"]
    requirement = f'identifier "{identifier}" and certificate leaf = H"{fingerprint}"'
    with operation_lock(directory):
        helper(directory, metadata, "unlock")
        try:
            with discoverable_keychain(metadata["keychainPath"]):
                run(["/usr/bin/codesign", "--force", "--sign", fingerprint,
                     "--keychain", metadata["keychainPath"], "--identifier", identifier,
                     "--requirements", "=designated => " + requirement,
                     "--timestamp=none", "--options", "runtime", app], timeout=60, diagnostic=True)
        finally:
            helper(directory, metadata, "lock")
    run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures",
         "--test-requirement", "=" + requirement, app])
    print(f"Signed and verified {app} with fixed certificate {fingerprint}.")


def status(args):
    directory = state_directory(args.state_dir)
    metadata = load_metadata(directory)
    helper(directory, metadata, "status")
    print(json.dumps({key: metadata[key] for key in (
        "identifier", "certificateSHA1", "certificateSHA256", "keychainPath")}, indent=2))
    print("Scoped signing password is readable without UI. This check did not unlock the dedicated Keychain.")
    print("Trust activation and screen-recording authorization are not inferred.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "activate-trust", "sign", "status"):
        sub = commands.add_parser(name)
        sub.add_argument("--state-dir", required=True, help="Explicit gitignored private signing directory")
        if name == "prepare":
            sub.add_argument("--identifier", default=DEFAULT_IDENTIFIER)
        if name == "sign":
            sub.add_argument("--identifier")
            sub.add_argument("app")
    args = parser.parse_args()
    if hasattr(args, "identifier") and args.identifier:
        # Keep the identifier safely representable in the requirement language.
        if any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" for c in args.identifier):
            raise SigningError("Identifier may contain only letters, digits, dots, and hyphens.")
    {"prepare": prepare, "activate-trust": activate_trust, "sign": sign, "status": status}[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except (SigningError, OSError) as error:
        print(f"Local signing stopped: {error}", file=sys.stderr)
        sys.exit(1)
