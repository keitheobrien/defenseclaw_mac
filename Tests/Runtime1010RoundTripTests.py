"""Opt-in installed-runtime contract test; every write is confined to a temporary home."""
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

python, plan_path = sys.argv[1:]
plan = json.loads(Path(plan_path).read_text())
with tempfile.TemporaryDirectory(prefix="defenseclawmac-1010-contract-", dir="/private/tmp") as directory:
    root = Path(directory)
    # Reserve a loopback port without listening, so no command can reach the live gateway.
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
        config = root / "config.yaml"
        config.write_text(f"config_version: 9\ndata_dir: {root}\nguardrail:\n  enabled: false\ngateway:\n  api_bind: 127.0.0.1\n  api_port: {port}\nrouting:\n  enabled: false\n")
        env = {key: os.environ[key] for key in ("PATH", "LANG", "TMPDIR") if key in os.environ}
        env.update(HOME=str(root), DEFENSECLAW_HOME=str(root), DEFENSECLAW_CONFIG=str(config), PYTHONDONTWRITEBYTECODE="1", NO_COLOR="1")
        cli_script = "from defenseclaw.main import cli; cli()"
        def invoke(args, *, script=cli_script, request=None, expected=0):
            result = subprocess.run([python, "-c", script, *args], input=None if request is None else json.dumps(request), text=True, capture_output=True, env=env, timeout=90)
            assert result.returncode == expected, (args, result.returncode, result.stdout[-1800:], result.stderr[-1000:])
            return result.stdout
        invoke(["config", "validate"])
        for args in plan["commands"]:
            invoke(args)
            print("PASS runtime CLI", " ".join(args[:3]), flush=True)
        import yaml
        written = yaml.safe_load(config.read_text())
        assert written["routing"]["models"][0]["name"] == "fixture"
        assert written["routing"]["default_alias"] == "fixture"
        assert not written["routing"].get("admin", {}).get("budgets")
        assert not written["routing"].get("admin", {}).get("rules")
        assert written["observability"]["pricing"]["models"][0]["input_per_mtok"] == 1
        invoke(["config", "set", "routing.classifier", "rules"])
        for key, value in [("guardrail.cascade.lanes.alignment", '"alert"'), ("decision_model.protocol", '"gemini-decisions"'), ("connectors.openclaw", '{"hooks":{"mode":"auto","prompt_gate":true},"install_policy":"on"}'), ("routing.context", plan["contextValue"])]:
            request = {"operation": "read", "key": key, "value": ""}
            read = invoke([], script=plan["configScript"], request=request)
            digest = read.split("DCRUNTIME_CONFIG_SHA:")[-1].strip()
            assert digest == hashlib.sha256(config.read_bytes()).hexdigest()
            request.update(operation="write", value=value, sha256=digest)
            invoke([], script=plan["configScript"], request=request)
            print("PASS secure runtime setting", key, flush=True)
        before = config.read_bytes()
        invoke([], script=plan["configScript"], request={"operation":"write", "key":"guardrail.cascade.lanes.alignment", "value":'"off"', "sha256":"0" * 64}, expected=1)
        assert config.read_bytes() == before, "stale config must not be overwritten"
        print("PASS stale configuration rejected without writing", flush=True)
        invoke([], script=plan["configScript"], request={"operation":"write", "key":"guardrail.cascade.lanes.alignment", "value":'"invalid lane"', "sha256":hashlib.sha256(before).hexdigest()}, expected=1)
        assert config.read_bytes() == before, "invalid config must not be written"
        print("PASS invalid configuration rejected without writing", flush=True)
        for args in [["setup", "tokenomics", "--enable"], ["setup", "tokenomics", "--disable"]]:
            invoke(args)
            print("PASS runtime CLI", " ".join(args), flush=True)
        written = yaml.safe_load(config.read_text())
        assert written["observability"]["tokenomics"]["enabled"] is False
        assert written["observability"]["tokenomics"]["local_store"]["enabled"] is False
        print("Runtime1010RoundTripTests passed; no live configuration or gateway used", flush=True)
