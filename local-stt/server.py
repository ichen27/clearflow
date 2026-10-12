"""Private, loopback-only ClearFlow API backed by MLX Whisper.
Audio stays in memory; the service does not log request bodies or transcripts.
Tailscale Serve supplies HTTPS and tailnet access control.
"""
import base64
import binascii
import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import re
import socket
import struct
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = "whisper-large-v3-turbo"
MAX_BODY = 14 * 1024 * 1024
MAX_AUDIO = 10 * 1024 * 1024
LANGUAGES = set("en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su yue".split())

class APIError(Exception):
    def __init__(self, status, code, message):
        self.status, self.code, self.message = status, code, message

def fail(status, code, message):
    raise APIError(status, code, message)

def validate_input(body):
    if not isinstance(body, dict):
        fail(400, "INVALID_REQUEST", "A JSON object is required.")
    rid = body.get("requestId")
    if not isinstance(rid, str) or not re.fullmatch(r"[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}", rid):
        fail(400, "INVALID_REQUEST_ID", "requestId must be a UUID.")
    language = body.get("language", "")
    if not isinstance(language, str):
        fail(400, "INVALID_LANGUAGE", "Use a supported Whisper language code.")
    language = language.strip().lower()
    if language in ("", "auto"):
        language = None
    elif language not in LANGUAGES:
        fail(400, "INVALID_LANGUAGE", "Use a supported Whisper language code.")
    vocabulary = body.get("vocabulary", "")
    if not isinstance(vocabulary, str) or len(vocabulary.encode("utf-16-le")) // 2 > 1000:
        fail(400, "INVALID_VOCABULARY", "Vocabulary must be at most 1000 characters.")
    encoded = body.get("audio")
    if not isinstance(encoded, str) or not encoded:
        fail(400, "INVALID_AUDIO", "Audio must be a base64 WAV file.")
    if len(encoded) > ((MAX_AUDIO + 2) // 3) * 4:
        fail(413, "AUDIO_TOO_LARGE", "Audio exceeds 10 MiB.")
    try:
        audio = base64.b64decode(encoded, validate=True)
        if base64.b64encode(audio).decode() != encoded:
            raise ValueError()
    except (ValueError, binascii.Error):
        fail(400, "INVALID_AUDIO", "Use canonical base64 audio.")
    if len(audio) > MAX_AUDIO:
        fail(413, "AUDIO_TOO_LARGE", "Audio exceeds 10 MiB.")
    try:
        if len(audio) < 44 or audio[:4] != b"RIFF" or audio[8:12] != b"WAVE" or struct.unpack_from("<I", audio, 4)[0] != len(audio)-8:
            raise ValueError()
        with wave.open(io.BytesIO(audio), "rb") as f:
            # This is ClearFlow's capture format; do not reinterpret other rates.
            if f.getnchannels() != 1 or f.getsampwidth() != 2 or f.getframerate() != 16000 or f.getcomptype() != "NONE":
                raise ValueError()
            frames = f.getnframes()
            if len(f.readframes(frames)) != frames * 2:
                raise ValueError()
    except (wave.Error, EOFError, ValueError, struct.error):
        fail(400, "INVALID_WAV", "Use a complete 16 kHz mono PCM16 WAV file.")
    if frames < 4000:
        fail(400, "AUDIO_TOO_SHORT", "Record at least a quarter of a second.")
    if frames > 4800000:
        fail(413, "AUDIO_TOO_LONG", "Recordings may not exceed five minutes.")
    return rid, audio, language, vocabulary.strip()

class LocalServer(ThreadingHTTPServer):
    daemon_threads = True
    def server_bind(self):
        # Avoid reverse DNS on startup; this service only binds loopback.
        socket.socket.bind(self.socket, self.server_address)
        self.server_address = self.socket.getsockname()
        self.server_name, self.server_port = self.server_address
    def handle_error(self, request, client_address):
        # Do not dump exception traces containing request data.
        print('{"event":"connection_failed"}', flush=True)

def make_server(token, infer, port=0):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ClearFlow"
        sys_version = ""
        def setup(self):
            super().setup()
            self.connection.settimeout(20)

        def log_message(self, *args):
            pass

        def reply(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            if status == 429:
                self.send_header("Retry-After", "5")
            if status == 401:
                self.send_header("WWW-Authenticate", "Bearer")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                self.reply(200, {"service": "clearflow-dictation", "model": MODEL, "backend": "mlx"})
            else:
                self.reply(405 if self.path == "/v1/transcribe" else 404,
                           {"error": {"code": "INVALID_ROUTE", "message": "Use POST /v1/transcribe."}})

        def do_POST(self):
            started = time.monotonic()
            request_id = None
            acquired = False
            try:
                if self.path != "/v1/transcribe":
                    fail(405 if self.path == "/health" else 404, "INVALID_ROUTE", "Use POST /v1/transcribe.")
                expected = self.server.auth_token
                if not expected:
                    fail(503, "NOT_CONFIGURED", "The transcription service is not configured.")
                match = re.fullmatch(r"Bearer ([^\s]+)", self.headers.get("Authorization", ""), re.I)
                supplied = match[1] if match else ""
                if not match or not hmac.compare_digest(hashlib.sha256(supplied.encode()).digest(), hashlib.sha256(expected.encode()).digest()):
                    fail(401, "UNAUTHORIZED", "A valid bearer token is required.")
                if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
                    fail(415, "UNSUPPORTED_MEDIA_TYPE", "Send application/json.")
                lengths = self.headers.get_all("Content-Length", [])
                if self.headers.get("Transfer-Encoding") or len(lengths) != 1 or not lengths[0].isdigit():
                    fail(400, "INVALID_LENGTH", "Send a single Content-Length.")
                length = int(lengths[0])
                if length > MAX_BODY:
                    fail(413, "BODY_TOO_LARGE", "The request exceeds 14 MiB.")
                # Bound memory and GPU work: no unbounded waiting queue.
                acquired = self.server.inference_lock.acquire(blocking=False)
                if not acquired:
                    fail(429, "BUSY", "The service is transcribing another recording. Try again shortly.")
                raw = self.rfile.read(length)
                try:
                    if len(raw) != length:
                        raise ValueError()
                    body = json.loads(raw)
                    request_id, audio, language, vocabulary = validate_input(body)
                except (ValueError, UnicodeError, RecursionError):
                    fail(400, "INVALID_JSON", "The body must be valid UTF-8 JSON.")
                try:
                    text = self.server.infer(audio, language, vocabulary).strip()
                except Exception:
                    fail(502, "TRANSCRIPTION_FAILED", "Local transcription failed. Please try again.")
                if not text:
                    fail(422, "NO_SPEECH", "No speech was detected. Try recording again.")
                self.reply(200, {"text": text, "requestId": request_id, "model": MODEL,
                                 "durationMs": round((time.monotonic() - started) * 1000, 1)})
            except APIError as e:
                self.reply(e.status, {"error": {"code": e.code, "message": e.message}})
            except (TimeoutError, ConnectionError, OSError):
                # Client disconnected or stopped uploading; release the slot.
                pass
            except Exception:
                self.reply(503, {"error": {"code": "SERVICE_UNAVAILABLE", "message": "The local service is unavailable."}})
            finally:
                if acquired:
                    self.server.inference_lock.release()

    server = LocalServer(("127.0.0.1", port), Handler)
    server.auth_token = token
    server.infer = infer
    server.inference_lock = threading.Lock()
    return server

class WhisperEngine:
    def __init__(self, model_path):
        import mlx.core as mx
        import numpy as np
        import mlx_whisper
        self.np, self.transcribe, self.model_path = np, mlx_whisper.transcribe, model_path
        # Preload weights and tokenizer; the model remains resident between requests.
        self.transcribe(np.zeros(16000, dtype=np.float32), path_or_hf_repo=model_path,
                        language="en", verbose=None, temperature=0.0)
    def __call__(self, audio, language, vocabulary):
        with wave.open(io.BytesIO(audio), "rb") as f:
            samples = self.np.frombuffer(f.readframes(f.getnframes()), dtype="<i2").astype(self.np.float32) / 32768.0
        # Exact digital silence should never produce hallucinated text.
        if not self.np.any(samples):
            return ""
        result = self.transcribe(samples, path_or_hf_repo=self.model_path,
                                 language=language, initial_prompt=vocabulary or None,
                                 verbose=None, temperature=0.0, condition_on_previous_text=False)
        return result["text"]

def main():
    from concurrent.futures import ThreadPoolExecutor
    config = json.loads(Path(os.environ["CLEARFLOW_SECRETS_FILE"]).read_text())
    token = config["AUTH_TOKEN"].strip()
    if len(token) < 32:
        raise SystemExit("Configure a private service token.")
    model_path = os.environ["CLEARFLOW_MODEL_PATH"]
    # MLX work runs on one persistent thread, including initialization.
    with ThreadPoolExecutor(max_workers=1) as pool:
        engine = pool.submit(WhisperEngine, model_path).result()
        def infer(*args):
            return pool.submit(engine, *args).result()
        server = make_server(token, infer, int(os.environ.get("CLEARFLOW_PORT", "8768")))
        print(json.dumps({"event": "ready", "model": MODEL, "port": server.server_port}), flush=True)
        server.serve_forever()

if __name__ == "__main__":
    main()
