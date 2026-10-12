#!/usr/bin/env python3
"""Start the local service, or configure the app without displaying a token."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from runtime import DEFAULT_RUNTIME, environment

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    parser.add_argument("--configure-app", type=Path, help="Path to ClearFlow.app")
    parser.add_argument("--endpoint", help="Your own HTTPS address when the app uses a remote Mac")
    args = parser.parse_args()
    runtime = args.runtime.expanduser().resolve()
    try:
        env = environment(runtime)
        if args.configure_app:
            token = json.loads((runtime / "secrets.json").read_text())["AUTH_TOKEN"]
            endpoint = args.endpoint or "http://127.0.0.1:" + env["CLEARFLOW_PORT"]
            binary = args.configure_app.expanduser().resolve() / "Contents/MacOS/ClearFlow"
            subprocess.run([str(binary), "--configure", endpoint], input=token, text=True, check=True)
        else:
            python = runtime / "venv/bin/python"
            server = Path(__file__).with_name("server.py").resolve()
            os.execve(str(python), [str(python), "-u", str(server)], dict(os.environ, **env))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, "Local setup is incomplete or app configuration failed. Run setup.py and check your paths.\n")

if __name__ == "__main__":
    main()
