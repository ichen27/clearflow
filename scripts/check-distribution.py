#!/usr/bin/env python3
"""Fail distribution checks for machine-specific configuration and private data."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, text=True).splitlines()
patterns = [
    re.compile(rb"/" + rb"(?:Users|Volumes)/[^\s\"']+"),
    re.compile(rb"https?://[a-z0-9.-]+\." + rb"ts\.net", re.I),
    re.compile(rb"https?://(?!example\.|YOUR-WORKER\.)[a-z0-9.-]+\." + rb"workers\.dev", re.I),
    re.compile(rb"gh[pousr]_" + rb"[A-Za-z0-9]{30,}"),
    re.compile(rb"-----BEGIN " + rb"(?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
errors = []
for name in sorted(set(files)):
    path = root / name
    if not path.is_file():
        continue
    if path.suffix in {".png", ".gif"}:
        continue
    data = path.read_bytes()
    if any(pattern.search(data) for pattern in patterns):
        errors.append(name + ": private endpoint, local path or credential marker")
config = json.loads((root / "worker/wrangler.jsonc").read_text())
if "account_id" in config:
    errors.append("Worker must select the deployer's account at setup")
info_path = root / "dist/ClearFlow.app/Contents/Info.plist"
if info_path.exists():
    info = plistlib.loads(info_path.read_bytes())
    if info.get("ClearFlowEndpoint") != "http://127.0.0.1:8768":
        errors.append("Release endpoint must be loopback")
    if info.get("CFBundleIdentifier") != "org.clearflow.app":
        errors.append("Release bundle identifier must be generic")
    if info.get("LSUIElement") is not False:
        errors.append("Release must be a Dock-visible application")
    if info.get("CFBundleIconFile") != "AppIcon":
        errors.append("Release must declare its app icon")
    icon = info_path.parent / "Resources/AppIcon.icns"
    if not icon.exists() or not icon.read_bytes().startswith(b"icns"):
        errors.append("Release must include a valid ICNS icon")
    bundle = info_path.parent.parent
    allowed = {"Contents/Info.plist", "Contents/Resources/AppIcon.icns", "Contents/MacOS/ClearFlow", "Contents/_CodeSignature/CodeResources"}
    for path in bundle.rglob("*"):
        if path.is_file():
            relative = path.relative_to(bundle).as_posix()
            if relative not in allowed or path.is_symlink():
                errors.append("Unexpected release bundle member: " + relative)
            if any(pattern.search(path.read_bytes()) for pattern in patterns):
                errors.append("Release bundle contains private paths, endpoints or credential markers")
    archive = root / "dist/ClearFlow-macOS-arm64.zip"
    if archive.exists():
        with zipfile.ZipFile(archive) as zipped:
            for member in zipped.infolist():
                if member.is_dir():
                    continue
                if member.filename not in {"ClearFlow.app/" + name for name in allowed}:
                    errors.append("Unexpected app ZIP member: " + member.filename)
                if any(pattern.search(zipped.read(member)) for pattern in patterns):
                    errors.append("App ZIP contains private paths, endpoints or credential markers")
if errors:
    raise SystemExit("\n".join(errors))
print("PASS: distributable source and available release bundle privacy checks")
