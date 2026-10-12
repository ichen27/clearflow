#!/usr/bin/env python3
"""Opt-in launch-at-login for the user's own local Whisper runtime."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
from runtime import DEFAULT_RUNTIME, LABEL, environment

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    args = parser.parse_args()
    runtime = args.runtime.expanduser().resolve()
    env = environment(runtime)
    project = Path(__file__).resolve().parent.parent
    python = runtime / "venv/bin/python"
    for path in [python, Path(env["CLEARFLOW_SECRETS_FILE"]), Path(env["CLEARFLOW_MODEL_PATH"]) / "config.json"]:
        if not path.exists():
            parser.error("Run setup.py first; a required runtime file is missing.")
    # launchd must open logs before the process can request removable-volume access.
    logs = Path.home() / "Library/Logs/ClearFlow"
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    logs.chmod(0o700)
    config = {
        "Label": LABEL, "ProgramArguments": [str(python), "-u", str(project / "local-stt/server.py")],
        "WorkingDirectory": str(project), "EnvironmentVariables": env,
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 30,
        "ProcessType": "Background", "Umask": 0o077,
        "StandardOutPath": str(logs / "service.stdout.log"),
        "StandardErrorPath": str(logs / "service.stderr.log"),
    }
    target = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True)
    if target.is_symlink():
        target.unlink()
    with open(target, "w", opener=lambda p, flags: os.open(p, flags, 0o600)) as f:
        f.write(plistlib.dumps(config).decode())
    target.chmod(0o600)
    subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)], check=True)
    print("Whisper will start at login. Approve normal macOS file-access prompts if shown.")

if __name__ == "__main__":
    main()
