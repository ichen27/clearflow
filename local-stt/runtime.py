"""Portable private runtime configuration shared by setup and launch tools."""
import json
import os
from pathlib import Path
import secrets

DEFAULT_RUNTIME = Path.home() / "Library/Application Support/ClearFlow/service"
MODEL_REPO = "mlx-community/whisper-large-v3-turbo"
MODEL_REVISION = "a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb"
LABEL = "org.clearflow.stt"

def prepare(runtime, port=8768):
    runtime = Path(runtime).expanduser().resolve()
    if not 1024 <= port <= 65535:
        raise ValueError("Use an unprivileged port between 1024 and 65535.")
    runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    runtime.chmod(0o700)
    token_file = runtime / "secrets.json"
    # Preserve an existing credential; rerunning setup must not lock out clients.
    if not token_file.exists():
        with open(token_file, "x", opener=lambda p, flags: os.open(p, flags, 0o600)) as f:
            json.dump({"AUTH_TOKEN": secrets.token_urlsafe(48)}, f)
    token_file.chmod(0o600)
    token = json.loads(token_file.read_text())["AUTH_TOKEN"]
    if not isinstance(token, str) or len(token.strip()) < 32:
        raise ValueError("Existing secrets.json must contain AUTH_TOKEN of at least 32 characters.")
    config = runtime / "service-config.json"
    config.write_text(json.dumps({"port": port}, indent=2) + "\n")
    config.chmod(0o600)
    for name in ("models", "huggingface", "tiktoken-cache", "numba-cache", "logs"):
        (runtime / name).mkdir(exist_ok=True, mode=0o700)
    return runtime

def environment(runtime):
    runtime = Path(runtime).expanduser().resolve()
    config = json.loads((runtime / "service-config.json").read_text())
    return {
        "CLEARFLOW_SECRETS_FILE": str(runtime / "secrets.json"),
        "CLEARFLOW_MODEL_PATH": str(runtime / "models/whisper-large-v3-turbo"),
        "CLEARFLOW_PORT": str(config["port"]),
        "HF_HOME": str(runtime / "huggingface"), "HF_HUB_OFFLINE": "1",
        "TIKTOKEN_CACHE_DIR": str(runtime / "tiktoken-cache"),
        "NUMBA_CACHE_DIR": str(runtime / "numba-cache"),
        "PYTHONDONTWRITEBYTECODE": "1",
    }
