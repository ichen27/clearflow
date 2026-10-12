"""HTTP contract tests; only expensive GPU inference is substituted."""
import base64
import http.client
import io
import json
import struct
import threading
import unittest
import wave
from server import make_server

ID = "876f3c24-273e-4ea9-ac1c-148222412b10"
TOKEN = "test-only-token-abcdefghijklmnopqrstuvwxyz"

def wav(seconds=.5):
    out = io.BytesIO()
    with wave.open(out, "wb") as f:
        f.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        f.writeframes(struct.pack("<h", 1000) * int(16000 * seconds))
    return out.getvalue()

class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.entered, self.release = threading.Event(), threading.Event()
        self.block = False
        self.result = "  Hello from the mini.  "
        def infer(audio, language, vocabulary):
            self.calls.append((audio, language, vocabulary))
            if self.block:
                self.entered.set()
                self.release.wait(3)
            if isinstance(self.result, Exception):
                raise self.result
            return self.result
        self.server = make_server(TOKEN, infer)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, payload=None, token=TOKEN, path="/v1/transcribe", method="POST", raw=None, content_type="application/json"):
        body = raw if raw is not None else json.dumps(payload if payload is not None else {
            "audio": base64.b64encode(wav()).decode(), "requestId": ID}).encode()
        c = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        c.request(method, path, body=body, headers={"Authorization": "Bearer " + token, "Content-Type": content_type})
        r = c.getresponse()
        status, headers, data = r.status, dict(r.getheaders()), r.read()
        c.close()
        try: data = json.loads(data)
        except ValueError: pass
        return status, headers, data

    def test_valid_audio_and_hints_return_matching_request(self):
        body = {"audio": base64.b64encode(wav()).decode(), "requestId": ID,
                "language": "EN", "vocabulary": "Exampletown, ClearFlow"}
        status, headers, data = self.request(body)
        self.assertEqual(status, 200)
        self.assertEqual(data["text"], "Hello from the mini.")
        self.assertEqual(data["requestId"], ID)
        self.assertEqual(data["model"], "whisper-large-v3-turbo")
        self.assertGreaterEqual(data["durationMs"], 0)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(self.calls, [(wav(), "en", "Exampletown, ClearFlow")])

    def test_health_identifies_local_model(self):
        status, _, data = self.request(method="GET", path="/health", token="")
        self.assertEqual(status, 200)
        self.assertEqual(data["model"], "whisper-large-v3-turbo")
        self.assertEqual(data["backend"], "mlx")

    def test_unauthorized_audio_never_reaches_model(self):
        self.assertEqual(self.request(token="wrong")[0], 401)
        self.assertEqual(self.calls, [])

    def test_missing_auth_configuration_fails_closed(self):
        self.server.auth_token = ""
        self.assertEqual(self.request()[0], 503)
        self.assertEqual(self.calls, [])

    def test_invalid_json(self):
        self.assertEqual(self.request(raw=b"{broken")[0], 400)

    def test_content_type(self):
        self.assertEqual(self.request(content_type="text/plain")[0], 415)

    def test_invalid_request_id(self):
        self.assertEqual(self.request({"audio": base64.b64encode(wav()).decode(), "requestId": "bad"})[0], 400)
        self.assertEqual(self.calls, [])

    def test_invalid_audio_and_truncated_wav(self):
        for audio in ["!!!!", base64.b64encode(wav()[:-10]).decode()]:
            self.assertEqual(self.request({"audio": audio, "requestId": ID})[0], 400)
        self.assertEqual(self.calls, [])

    def test_duration_bounds(self):
        for seconds, status in [(.1, 400), (301, 413)]:
            self.assertEqual(self.request({"audio": base64.b64encode(wav(seconds)).decode(), "requestId": ID})[0], status)
        self.assertEqual(self.calls, [])

    def test_rejects_invalid_hints(self):
        for hints in [{"language": "xx"}, {"language": 3}, {"vocabulary": "x" * 1001}]:
            self.assertEqual(self.request({"audio": base64.b64encode(wav()).decode(), "requestId": ID, **hints})[0], 400)
        self.assertEqual(self.calls, [])

    def test_auto_language(self):
        self.assertEqual(self.request({"audio": base64.b64encode(wav()).decode(), "requestId": ID, "language": "auto"})[0], 200)
        self.assertIsNone(self.calls[0][1])

    def test_no_speech(self):
        self.result = " "
        self.assertEqual(self.request()[0], 422)

    def test_model_failure_does_not_leak_details(self):
        self.result = RuntimeError("private audio or secrets")
        status, _, data = self.request()
        self.assertEqual(status, 502)
        self.assertNotIn("private", json.dumps(data))

    def test_busy_rejected_without_concurrent_inference(self):
        self.block = True
        t = threading.Thread(target=self.request)
        t.start()
        self.assertTrue(self.entered.wait(2))
        try:
            self.assertEqual(self.request()[0], 429)
            self.assertEqual(len(self.calls), 1)
        finally:
            self.release.set()
            t.join()

    def test_unknown_route_and_wrong_method(self):
        self.assertEqual(self.request(path="/other")[0], 404)
        self.assertEqual(self.request(path="/health")[0], 405)
        self.assertEqual(self.request(method="GET")[0], 405)

    def test_oversized_body(self):
        c = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        c.request("POST", "/v1/transcribe", headers={"Authorization": "Bearer " + TOKEN,
                  "Content-Type": "application/json", "Content-Length": str(14 * 1024 * 1024 + 1)})
        r = c.getresponse()
        self.assertEqual(r.status, 413)
        r.read()
        c.close()

if __name__ == "__main__":
    unittest.main()
