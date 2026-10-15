#!/usr/bin/env python3
"""Opt-in native rendering smoke test against a disposable CLI/API fixture."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

if sys.argv[1:] not in (["--run-gui"], ["--run-sandbox-gui"], ["--run-upgrade-gui"], ["--run-inspection-gui"]):
    print("SKIP PanelNativeSmokeTests: use --run-gui, --run-sandbox-gui, --run-upgrade-gui, or --run-inspection-gui in a macOS desktop session.")
    sys.exit(0)
repo = Path(__file__).resolve().parent.parent
root = Path(tempfile.mkdtemp(prefix="defenseclawmac-panel-tests-"))
print("Native panel artifacts:", root, flush=True)
for name in ("DefenseClawMac", "DefenseClawMac.xcodeproj", "GatewayAdminHelper", "script"):
    shutil.copytree(repo / name, root / name, ignore=shutil.ignore_patterns("__pycache__", "xcuserdata"))
entry = root / "DefenseClawMac/App/DefenseClawApp.swift"
entry.write_text(entry.read_text().replace("@main\nstruct DefenseClawApp", "struct DefenseClawApp", 1))
shutil.copy2(repo / "Tests/PanelNativeSmokeTests.swift", root / "DefenseClawMac/App/PanelNativeSmokeTests.swift")
with (root / "build.log").open("w") as log:
    subprocess.run(["xcodebuild", "-project", str(root / "DefenseClawMac.xcodeproj"),
                    "-scheme", "DefenseClawMac", "-configuration", "Debug", "-destination", "generic/platform=macOS",
                    "-derivedDataPath", str(root / "build"), "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=-",
                    "DEVELOPMENT_TEAM=", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "PRODUCT_BUNDLE_IDENTIFIER=com.keitheobrien.DefenseClawMac.ParityTest",
                    "build"], stdout=log, stderr=subprocess.STDOUT, check=True)
server = subprocess.Popen([sys.executable, "-u", str(repo / "Tests/Support/parity_fixture.py"), "--serve"],
                          stdout=subprocess.PIPE, text=True)
try:
    fixture = json.loads(server.stdout.readline())
    print("Fixture:", fixture, flush=True)
    fixture_root = Path(fixture["root"])
    env = {key: os.environ[key] for key in ("PATH", "HOME", "USER", "TMPDIR", "LANG", "LOGNAME") if key in os.environ}
    env.update(DEFENSECLAW_HOME=str(fixture_root), DEFENSECLAW_CONFIG=str(fixture_root / "config.yaml"),
               DEFENSECLAW_VENV=os.environ.get("DEFENSECLAW_TEST_VENV", str(repo.parent / "defenseclaw/.venv")), PYTHONDONTWRITEBYTECODE="1",
               PARITY_SCREENSHOTS=str(root / "screenshots"))
    if sys.argv[1:] == ["--run-inspection-gui"]:
        env["PARITY_INSPECTION_ONLY"] = "1"
    if sys.argv[1:] == ["--run-sandbox-gui"]:
        env["PARITY_SANDBOX_ONLY"] = "1"
    if sys.argv[1:] == ["--run-upgrade-gui"]:
        fixture_root = Path(str(fixture_root).replace("/private/tmp/", "/tmp/", 1))
        env.update(PARITY_UPGRADE_ONLY="1", HOME=str(fixture_root), CFFIXED_USER_HOME=str(fixture_root),
                   DEFENSECLAW_HOME=str(fixture_root), DEFENSECLAW_CONFIG=str(fixture_root / "config.yaml"),
                   DEFENSECLAW_VENV=str(fixture_root / ".venv"))
    binary = root / "build/Build/Products/Debug/DefenseClawMac.app/Contents/MacOS/DefenseClawMac"
    args = [str(binary), "-defenseclawBinaryPath", str(fixture_root / "bin/defenseclaw"),
            "-startGatewayAutomatically", "NO", "-gatewayAdministratorMode", "NO",
            "-notifyCritical", "NO", "-notifyHigh", "NO", "-notifyGatewayOffline", "NO", "-notifySandboxEvents", "NO"]
    with (root / "run.log").open("w") as log:
        result = subprocess.run(args, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
    output = (root / "run.log").read_text()
    print(output)
    if result.returncode or "PASS all native panel/form renders completed" not in output:
        sys.exit(1)
finally:
    server.terminate()
    server.wait(timeout=10)
