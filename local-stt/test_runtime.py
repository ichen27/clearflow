import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from runtime import prepare, environment
import importlib
from server import wired_limit, WIRED_HEADROOM

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
    def test_wired_limit_covers_peak_and_stays_below_system_cap(self):
        gib = 1024 ** 3
        self.assertEqual(wired_limit(3 * gib, 12 * gib), 3 * gib + WIRED_HEADROOM)
        self.assertEqual(wired_limit(12 * gib, 12 * gib), int(12 * gib * 0.9))
        self.assertEqual(wired_limit(0, 12 * gib), 0)
        self.assertEqual(wired_limit(3 * gib, 0), 0)
    def test_launch_agent_is_not_throttled_as_background_work(self):
        agent = importlib.import_module("install-agent")
        self.assertEqual(agent.PROCESS_TYPE, "Interactive")
