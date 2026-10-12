import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from runtime import prepare, environment

class RuntimeTests(unittest.TestCase):
    def test_independent_runtimes_have_unique_credentials_and_private_files(self):
        with tempfile.TemporaryDirectory() as directory:
            a = prepare(Path(directory) / "first")
            b = prepare(Path(directory) / "second", 18768)
            self.assertNotEqual((a / "secrets.json").read_text(), (b / "secrets.json").read_text())
            self.assertEqual(environment(b)["CLEARFLOW_PORT"], "18768")
            self.assertEqual(environment(a)["HF_HUB_OFFLINE"], "1")
            for runtime in [a, b]:
                self.assertEqual(stat.S_IMODE(runtime.stat().st_mode), 0o700)
                for filename in ["secrets.json", "service-config.json"]:
                    self.assertEqual(stat.S_IMODE((runtime / filename).stat().st_mode), 0o600)
                self.assertTrue(environment(runtime)["CLEARFLOW_MODEL_PATH"].startswith(str(runtime)))
    def test_rerun_preserves_token(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = prepare(directory)
            original = (runtime / "secrets.json").read_text()
            prepare(directory)
            self.assertEqual((runtime / "secrets.json").read_text(), original)
    def test_bad_existing_secret_is_not_silently_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = prepare(directory)
            (runtime / "secrets.json").write_text('{"AUTH_TOKEN":"short"}')
            with self.assertRaises(ValueError): prepare(directory)
    def test_invalid_port_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for port in [0, 80, 65536]:
                with self.assertRaises(ValueError): prepare(directory, port)
