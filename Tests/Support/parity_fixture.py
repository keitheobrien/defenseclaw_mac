#!/usr/bin/env python3
"""Disposable UI fixture. Never starts a DefenseClaw gateway or scans the host.
Run with --serve; stdout reports a temporary root, CLI and loopback port.
The mock CLI only reads/writes files under that root. Policy/config catalogs
use the separately selected real runtime interpreter in read-only mode.
"""
import datetime
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def cli():
    root = Path(__file__).resolve().parent.parent
    args = sys.argv[1:]
    with (root / "commands.jsonl").open("a") as handle:
        handle.write(json.dumps(args) + "\n")
    if "--version" in args or args == ["version"]:
        print("defenseclaw, version 1.0.0")
    elif "--help" in args:
        print("Usage: defenseclaw [OPTIONS] COMMAND\nCommands:\n  redaction  Redaction policy\n  codex  Codex\n  amp  Amp\n  scan  Scan\n  enable  Enable\n  disable  Disable\n  selftest  Self-test\n  findings  Findings")
    elif args[:4] == ["sandbox", "pack", "list", "-o"]:
        print(json.dumps({"packs": [{"name": "open", "builtin": True, "profile": "open", "description": "Synthetic fixture sandbox pack"}]}))
    elif args[:2] == ["guardrail", "validate-pack"]:
        print('{"valid": true, "summary": {"rule_count": 10}}')
    elif len(args) >= 2 and args[0] in ("skill", "mcp", "plugin", "tool") and args[1] == "list":
        resource = args[0]
        key = {"skill": "skills", "mcp": "mcp_servers", "plugin": "plugins", "tool": "tools"}[resource]
        row = dict(name="Fixture " + resource, id="fixture-" + resource, connector="codex", description="Synthetic catalog row",
                   version="1.0", status="active", source="fixture", eligible=True, enabled=True,
                   transport="stdio", command="fixture-tool", actions={"install": "allow", "runtime": "enable"})
        print(json.dumps([{"connector": "codex", key: [row]}]))
    elif args[:2] == ["aibom", "scan"]:
        print(json.dumps([{"connector": "codex", "skills": [{"name": "Fixture skill", "path": str(root / "skill"), "eligible": True}],
                           "mcp_servers": [{"name": "Fixture MCP", "transport": "stdio"}], "plugins": [], "tools": [],
                           "agents": [], "models": [], "model_providers": [], "memory": []}]))
    elif args[:3] == ["setup", "redaction", "status"]:
        print("Synthetic fixture: default sensitive; no external destinations. No real policy was read.")
    else:
        print("Fixture command completed; no production installation was changed.")


def serve():
    root = Path(tempfile.mkdtemp(prefix="defenseclawmac-parity-", dir="/private/tmp"))
    (root / "bin").mkdir()
    (root / "bin/defenseclaw").write_text(Path(__file__).read_text())
    (root / "bin/defenseclaw").chmod(0o755)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    db = sqlite3.connect(root / "audit.db")
    db.execute("CREATE TABLE audit_events (id TEXT, timestamp TEXT, bucket TEXT, event_name TEXT, source TEXT, signal TEXT, severity TEXT, action TEXT, actor TEXT, details TEXT, connector TEXT, payload_json TEXT, projected_record_json TEXT, target TEXT)")
    for i, bucket in enumerate(("security.finding", "compliance.activity", "network.egress", "guardrail.evaluation")):
        record = {"message": "Synthetic fixture event", "severity": "HIGH", "action": "block", "connector": "codex"}
        db.execute("INSERT INTO audit_events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (str(i), now, bucket, "fixture.event", "fixture", "logs", "HIGH", "block", "fixture", "Synthetic fixture detail", "codex", json.dumps(record), json.dumps(record), "codex:fixture"))
    db.commit()
    db.close()
    (root / "gateway.log").write_text("INFO Synthetic gateway ready\nWARN Synthetic fixture warning\n")
    (root / "watchdog.log").write_text("INFO Synthetic watchdog ready\n")
    signals = [{"product": "Codex", "vendor": "OpenAI", "category": "ai_cli", "detector": "binary", "state": "active", "confidence": 0.95},
               {"product": "Fixture Models", "vendor": "Fixture", "category": "local_model", "detector": "model_api", "state": "active", "confidence": 0.95,
                "model": {"id": "fixture/model", "status": "loaded", "format": "gguf", "modality": "text", "relevance": "primary", "owner_application": "Fixture Models", "discovery_confidence": 0.96}}]
    sandbox = {"name": "fixture-codex", "harness": "codex", "phase": "ready", "pack": "open", "profile": "open", "workdir_mode": "copy", "project": str(root), "egress": {"blocked": 1, "destinations": 2}, "hooks": {"tool_calls": 3}}
    replies = {
        "/health": {"state": "running", "version": "1.0.0", "uptime_ms": 100000, "guardrail": {"state": "running"}, "watcher": {"state": "running"}, "connectors": [{"name": "codex", "state": "running", "requests": 5}]},
        "/api/v1/ai-usage": {"enabled": True, "signals": signals, "summary": {"active_signals": 2, "files_scanned": 10, "scanned_at": now}},
        "/api/v1/ai-usage/runtime": {"enabled": True, "planes": [{"name": "agent actions", "running": True, "available": True}], "findings": [], "last_poll": now},
        "/api/v1/sandbox/status": {"enabled": True, "available": True, "running": 1, "sandboxes": 1, "gateway": {"name": "fixture", "driver": "vm"}},
        "/api/v1/sandbox/sandboxes": {"sandboxes": [sandbox]},
        "/api/v1/sandbox/approvals": {"approvals": [{"id": "fixture-ask", "sandbox": "fixture-codex", "host": "example.invalid", "port": 443, "kind": "egress", "status": "pending"}]},
        "/api/v1/sandbox/activity": {"events": [{"seq": 1, "kind": "egress.blocked", "sandbox": "fixture-codex", "host": "example.invalid", "unblockable": True, "message": "Synthetic block"}]},
    }
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            path = self.path.split("?")[0]
            if (root / "offline").exists():
                self.send_response(503); self.end_headers(); return
            payload = replies.get(path, {})
            body = json.dumps(payload).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
        def do_POST(self):
            self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 4096))
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b'{"ok":true}')
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    (root / "config.yaml").write_text(f"config_version: 8\ndata_dir: {root}\naudit_db: {root}/audit.db\npolicy_dir: {root}/policies\nclaw:\n  mode: codex\nguardrail:\n  enabled: true\n  mode: observe\n  connectors:\n    codex:\n      enabled: true\n      mode: observe\ngateway:\n  host: 127.0.0.1\n  port: {port}\n  api_port: {port}\nopenshell:\n  enabled: true\nai_discovery:\n  enabled: true\nobservability:\n  defaults:\n    redaction_profile: sensitive\n")
    print(json.dumps({"root": str(root), "port": port, "cli": str(root / "bin/defenseclaw")}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    if sys.argv[1:] == ["--serve"]:
        serve()
    else:
        cli()
