#!/usr/bin/env python3
"""Build, optionally notarize, and package a signed Sparkle beta feed locally."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_app import ROOT, CONFIG, SPARKLE, build_app, run
from release_settings import load_release_settings


def package(args):
    if args.notary_profile and args.identity == "-":
        raise ValueError("Notarization requires a Developer ID Application identity.")
    dist = ROOT / "release-dist"
    work = ROOT / ".release-work"
    dist.mkdir(exist_ok=True)
    work.mkdir(exist_ok=True)
    app_notarized = False
    if args.prepared_app:
        app = args.prepared_app.resolve()
        with (app / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if info.get("CFBundleIdentifier") != CONFIG["bundle_id"] or info.get("CFBundleVersion") != CONFIG["build"]:
            raise ValueError("Prepared app does not match the configured release.")
        run("codesign", "--verify", "--deep", "--strict", app)
        if args.notarized_app:
            run("xcrun", "stapler", "validate", app)
            run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
            app_notarized = True
    else:
        if args.notarized_app:
            raise ValueError("--notarized-app requires --prepared-app")
        app = build_app(dist / "CursorSwitch.app", universal=True, updates=True, identity=args.identity)
    if args.notary_profile:
        archive = work / "notarization.zip"
        archive.unlink(missing_ok=True)
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        run("xcrun", "notarytool", "submit", archive, "--keychain-profile", args.notary_profile,
            "--wait", "--output-format", "json", stdout=(dist / "notarization-app.json").open("w"))
        result = json.loads((dist / "notarization-app.json").read_text())
        if result.get("status") != "Accepted":
            raise RuntimeError(f"Notarization was not accepted: {result.get('status')}")
        run("xcrun", "stapler", "staple", app)
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
        app_notarized = True

    stage = work / "dmg-root"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    run("ditto", app, stage / "Cursor Switch.app")
    shutil.copy2(ROOT / "LICENSE", stage / "LICENSE.txt")
    (stage / "Applications").symlink_to("/Applications")
    signed_note = ("This beta app is Developer ID signed and notarized by Apple.\n" if app_notarized else
                   "This beta is not notarized. macOS may block its first launch.\n")
    (stage / "Read Me.txt").write_text(
        "CURSOR SWITCH — BETA\n\n"
        "1. Drag Cursor Switch.app to Applications.\n"
        "2. Eject this disk image.\n"
        "3. Open Cursor Switch from Applications. Its icon appears in the menu bar, not the Dock.\n\n"
        "Choose Default or Custom from the menu bar. Customize… opens shapes, symbols, emoji, and image import.\n"
        "Control–Option–Command–C switches cursors. Quit restores the normal macOS cursor.\n\n"
        "Use Check for Updates… in the menu bar for later test builds.\n"
        "Requires macOS 15 or newer. Supports Apple Silicon and Intel Macs.\n\n" + signed_note +
        "\nLicensed under GPLv3. Source code for this release:\n"
        f"https://github.com/{CONFIG['repository']}/tree/v{CONFIG['version']}\n")

    dmg = dist / f"CursorSwitch-{CONFIG['version']}.dmg"
    dmg.unlink(missing_ok=True)
    run("hdiutil", "create", "-volname", "Cursor Switch", "-srcfolder", stage,
        "-fs", "APFS", "-format", "ULFO", dmg)
    if args.identity != "-":
        run("codesign", "--sign", args.identity, "--timestamp", dmg)
    if args.notary_profile:
        run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", args.notary_profile,
            "--wait", "--output-format", "json", stdout=(dist / "notarization-dmg.json").open("w"))
        result = json.loads((dist / "notarization-dmg.json").read_text())
        if result.get("status") != "Accepted":
            raise RuntimeError(f"DMG notarization was not accepted: {result.get('status')}")
        run("xcrun", "stapler", "staple", dmg)
        run("xcrun", "stapler", "validate", dmg)
    run("hdiutil", "verify", dmg)
    (dist / f"{dmg.name}.sha256").write_text(f"{hashlib.sha256(dmg.read_bytes()).hexdigest()}  {dmg.name}\n")

    # Only archives go in this folder. Re-sign after ALL notarization/stapling.
    feed_dir = work / "appcast"
    if feed_dir.exists():
        shutil.rmtree(feed_dir)
    feed_dir.mkdir()
    shutil.copy2(dmg, feed_dir / dmg.name)
    release_notes = ROOT / "distribution/release-notes.md"
    shutil.copy2(release_notes, feed_dir / f"{dmg.stem}.md")
    # generate_keys owns this Keychain item. Export only into an owner-only
    # temporary directory so the other Sparkle tools need no extra Keychain ACL.
    # Never print or retain the private key, and remove it even on signing errors.
    with tempfile.TemporaryDirectory(prefix="signing-", dir=work) as directory:
        private_key = Path(directory) / "sparkle.key"
        previous_umask = os.umask(0o077)
        try:
            run(SPARKLE / "bin/generate_keys", "--account", args.sparkle_account, "-x", private_key)
        finally:
            os.umask(previous_umask)
        private_key.chmod(0o600)
        run(SPARKLE / "bin/generate_appcast", "--ed-key-file", private_key,
            "--download-url-prefix", f"https://github.com/{CONFIG['repository']}/releases/download/v{CONFIG['version']}/",
            "--embed-release-notes", "--maximum-deltas", "0", feed_dir)
        run(SPARKLE / "bin/sign_update", "--ed-key-file", private_key, "--verify", feed_dir / "appcast.xml")
    shutil.copy2(feed_dir / "appcast.xml", dist / "appcast.xml")
    (dist / "release-manifest.json").write_text(json.dumps({
        "version": CONFIG["version"], "build": CONFIG["build"], "dmg": dmg.name,
        "architectures": ["arm64", "x86_64"], "app_notarized": app_notarized,
        "dmg_notarized": bool(args.notary_profile),
        "identity": args.identity, "feed_url": CONFIG["feed_url"]
    }, indent=2) + "\n")
    print(f"Packaged: {dmg}")


if __name__ == "__main__":
    settings = load_release_settings()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", default=settings.get("signing_identity", "-"))
    parser.add_argument("--notary-profile", default=settings.get("notary_profile"))
    parser.add_argument("--sparkle-account", default=settings.get("sparkle_key_account"), help="Sparkle Keychain account (or CURSOR_SPARKLE_KEY_ACCOUNT)")
    parser.add_argument("--prepared-app", type=Path)
    parser.add_argument("--notarized-app", action="store_true")
    args = parser.parse_args()
    if not args.sparkle_account:
        parser.error("Provide --sparkle-account, CURSOR_SPARKLE_KEY_ACCOUNT, or local release settings.")
    package(args)
