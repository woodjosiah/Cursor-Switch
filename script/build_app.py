#!/usr/bin/env python3
"""Build a self-contained app; never launch or change the running copy."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "distribution/release.json").read_text())
SPARKLE = ROOT / ".build/artifacts/sparkle/Sparkle"


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def build_app(output: Path, *, universal=False, updates=False, identity="-"):
    output = output.resolve()
    if output.suffix != ".app" or output.parent not in (ROOT / "dist", ROOT / "release-dist"):
        raise ValueError("Output must be an app directly inside dist/ or release-dist/.")
    if updates and len(base64.b64decode(CONFIG["sparkle_public_key"], validate=True)) != 32:
        raise ValueError("Invalid Sparkle public key")
    sdk_version = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()
    # SwiftPM's linker can otherwise stamp the deployment minimum as the SDK
    # version, which opts native controls into legacy appearance. Record the
    # SDK actually used, while keeping the macOS 15 deployment minimum.
    flags = ["-c", "release", "-Xlinker", "-platform_version", "-Xlinker", "macos",
             "-Xlinker", CONFIG["minimum_macos"], "-Xlinker", sdk_version]
    if universal:
        flags += ["--arch", "arm64", "--arch", "x86_64"]
    run("swift", "build", *flags, cwd=ROOT)
    bin_dir = Path(subprocess.check_output(["swift", "build", *flags, "--show-bin-path"], cwd=ROOT, text=True).strip())
    framework = SPARKLE / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    if not framework.is_dir():
        raise RuntimeError("The pinned Sparkle framework was not resolved.")
    if output.exists():
        shutil.rmtree(output)
    contents = output / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    (contents / "Resources").mkdir()
    shutil.copy2(bin_dir / "CursorSwitch", contents / "MacOS/CursorSwitch")
    run("ditto", framework, contents / "Frameworks/Sparkle.framework")
    shutil.copy2(SPARKLE / "LICENSE", contents / "Resources/Sparkle-LICENSE.txt")
    shutil.copy2(ROOT / "LICENSE", contents / "Resources/LICENSE.txt")

    plist = {
        "CFBundleExecutable": "CursorSwitch",
        "CFBundleIdentifier": CONFIG["bundle_id"],
        "CFBundleName": "Cursor Switch",
        "CFBundleDisplayName": "Cursor Switch",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": CONFIG["version"],
        "CFBundleVersion": CONFIG["build"],
        "LSMinimumSystemVersion": CONFIG["minimum_macos"],
        "LSUIElement": True,
        "NSPrincipalClass": "NSApplication",
        "NSHighResolutionCapable": True,
        "CSUpdatesEnabled": updates,
        "SUFeedURL": CONFIG["feed_url"],
        "SUPublicEDKey": CONFIG["sparkle_public_key"],
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
        "SUEnableSystemProfiling": False,
        "SUAutomaticallyUpdate": False,
        "SUScheduledCheckInterval": 86400,
    }
    # Compile the editable Icon Composer document into the native layered icon
    # and the backwards-compatible ICNS, even on a fresh checkout.
    icon_work = ROOT / ".release-work"
    icon_work.mkdir(exist_ok=True)
    icon_info = icon_work / "AppIcon-Info.plist"
    run("xcrun", "actool", ROOT / "Resources/AppIcon.icon",
        "--compile", contents / "Resources", "--platform", "macosx",
        "--minimum-deployment-target", CONFIG["minimum_macos"], "--app-icon", "AppIcon",
        "--output-partial-info-plist", icon_info, "--output-format", "human-readable-text")
    with icon_info.open("rb") as file:
        plist.update(plistlib.load(file))
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(plist, file)

    # Sign nested executables first. Do not use --deep for signing.
    embedded = contents / "Frameworks/Sparkle.framework"
    signing_options = ["--force", "--sign", identity]
    if identity != "-":
        signing_options += ["--options", "runtime", "--timestamp"]
    code = [embedded / "Versions/B/Autoupdate",
            embedded / "Versions/B/Updater.app",
            embedded / "Versions/B/XPCServices/Downloader.xpc",
            embedded / "Versions/B/XPCServices/Installer.xpc",
            embedded, output]
    for item in code:
        if item.exists():
            run("codesign", *signing_options, item)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", output)
    run("plutil", "-lint", contents / "Info.plist")
    if universal:
        architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(contents / "MacOS/CursorSwitch")], text=True).split()
        if not {"arm64", "x86_64"}.issubset(architectures):
            raise RuntimeError(f"Universal app is missing an architecture: {architectures}")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/CursorSwitch.app")
    parser.add_argument("--universal", action="store_true")
    parser.add_argument("--updates", action="store_true")
    parser.add_argument("--identity", default=os.environ.get("CURSOR_SIGNING_IDENTITY", "-"))
    args = parser.parse_args()
    print(build_app(args.output, universal=args.universal, updates=args.updates, identity=args.identity))
