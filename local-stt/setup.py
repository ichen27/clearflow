#!/usr/bin/env python3
"""Install pinned dependencies and model into a user-owned runtime directory."""
import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path
from runtime import DEFAULT_RUNTIME, MODEL_REPO, MODEL_REVISION, prepare, environment

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    parser.add_argument("--port", type=int, default=8768)
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("The MLX backend requires an Apple Silicon Mac.")
    if sys.version_info[:2] != (3, 12):
        parser.error("Run setup with Python 3.12 to match requirements.lock.")
    runtime = prepare(args.runtime, args.port)
    python = runtime / "venv/bin/python"
    if not python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(runtime / "venv")], check=True)
    env = dict(os.environ, **environment(runtime))
    # Only installation downloads; the server runs with Hugging Face offline mode.
    env["HF_HUB_OFFLINE"] = "0"
    subprocess.run([str(python), "-m", "pip", "install", "-r",
                    str(Path(__file__).with_name("requirements.lock"))], env=env, check=True)
    download = "from huggingface_hub import snapshot_download; import sys; snapshot_download(repo_id=sys.argv[1],revision=sys.argv[2],local_dir=sys.argv[3])"
    subprocess.run([str(python), "-c", download, MODEL_REPO, MODEL_REVISION,
                    env["CLEARFLOW_MODEL_PATH"]], env=env, check=True)
    print("Installed local Whisper. Start it with local-stt/run.py using the same --runtime if customized.")
    print("The access token is in secrets.json inside your private runtime directory; setup never prints it.")

if __name__ == "__main__":
    main()
