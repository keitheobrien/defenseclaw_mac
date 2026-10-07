#!/usr/bin/env python3
"""Read-only contract tests against the selected runtime; no live config or daemon."""
import importlib.util
import sys
import json
import tempfile
import subprocess
import os
import unittest
from pathlib import Path
from unittest.mock import patch
from defenseclaw.config import Config, PerConnectorGuardrailConfig
from defenseclaw.tui.policy_panel import read_policy_catalog

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("bridge", ROOT / "DefenseClawMac/Resources/policy_catalog_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class PolicyCatalogBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cfg = Config(data_dir=self.temp.name, policy_dir=self.temp.name + "/policies")
        self.cfg.guardrail.mode = "action"
        self.cfg.guardrail.block_at = "MEDIUM"
        self.cfg.guardrail.connectors = {"codex": PerConnectorGuardrailConfig(mode="action", block_at="HIGH")}

    def catalog(self):
        return bridge.snapshot(self.cfg, '{"packs":[{"name":"open","builtin":true,"profile":"open"}]}')

    def test_seven_views_scopes_and_read_only_details(self):
        before = list(Path(self.temp.name).rglob("*"))
        data = self.catalog()
        self.assertEqual(set(v["id"] for v in data["views"]),
                         {"posture", "optin", "chains", "families", "policies", "packs", "sandbox_packs"})
        self.assertIn("codex", data["scopes"])
        for view in data["views"]:
            self.assertFalse(view["error"], view["error"])
            for row in view["rows"]:
                self.assertEqual(len(row["cells"]), len(view["columns"]))
                self.assertTrue(row["detail"])
                if view["id"] in ("chains", "families", "sandbox_packs"):
                    self.assertFalse(row["actions"])
        self.assertEqual(before, list(Path(self.temp.name).rglob("*")), "catalog reads must not write")

    def test_threshold_scope_weakening_and_command_separation(self):
        views = self.catalog()["views"]
        posture = next(v for v in views if v["id"] == "posture")
        codex = next(r for r in posture["rows"] if r["cells"][0] == "codex")
        weaker = next(a for a in codex["actions"] if a["arguments"] == ["guardrail", "block-at", "CRITICAL", "--connector", "codex"])
        self.assertTrue(weaker["weaker"])
        self.assertIn("HIGH+ → CRITICAL", weaker["consequence"])
        approval = next(a for a in codex["actions"] if a["arguments"][:3] == ["guardrail", "hilt", "off"])
        self.assertEqual(approval["arguments"][-3:], ["--connector", "codex", "--yes"])
        policy = next(v for v in views if v["id"] == "policies")
        edits = [a for r in policy["rows"] for a in r["actions"] if a["group"].startswith("LLM")]
        self.assertTrue(edits)
        for action in edits:
            self.assertEqual(action["arguments"][:3], ["policy", "edit", "guardrail"])
            self.assertIn("LLM traffic", action["consequence"])

    def test_partial_errors_are_visible_and_sandbox_failure_is_not_empty_success(self):
        read = read_policy_catalog(self.cfg)
        read.posture_error = "Synthetic unreadable rule file"
        with patch("defenseclaw.tui.policy_panel.read_policy_catalog", return_value=read):
            data = bridge.snapshot(self.cfg, sandbox_error="Synthetic sandbox unavailable")
        self.assertIn("Synthetic unreadable", next(v for v in data["views"] if v["id"] == "posture")["error"])
        self.assertIn("Synthetic sandbox unavailable", next(v for v in data["views"] if v["id"] == "sandbox_packs")["error"])
        self.assertTrue(next(v for v in data["views"] if v["id"] == "policies")["rows"])

    def test_old_runtime_reports_actionable_error_without_traceback(self):
        root = Path(self.temp.name)
        package = root / "defenseclaw"
        (package / "tui").mkdir(parents=True)
        (package / "__init__.py").write_text("")
        (package / "tui/__init__.py").write_text("")
        (package / "config.py").write_text("def load():\n    return None\n")
        env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([sys.executable, str(ROOT / "DefenseClawMac/Resources/policy_catalog_bridge.py")],
                                input="{}", text=True, capture_output=True, env=env, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Settings > Connection", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(result.stdout)


if __name__ == "__main__":
    unittest.main()
