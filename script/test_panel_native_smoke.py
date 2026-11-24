#!/usr/bin/env python3
"""Opt-in native rendering smoke test against a disposable CLI/API fixture."""
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

if sys.argv[1:] not in (["--run-gui"], ["--run-sandbox-gui"], ["--run-upgrade-gui"], ["--run-opencode-upgrade-gui"], ["--run-inspection-gui"], ["--run-runtime1010-gui"]):
    print("SKIP PanelNativeSmokeTests: use --run-gui, --run-sandbox-gui, --run-upgrade-gui, --run-opencode-upgrade-gui, --run-inspection-gui, or --run-runtime1010-gui in a macOS desktop session.")
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
# Give the disposable app a distinct process name. System Events otherwise
# serializes UI element references by the installed app's identical name.
app_bundle = root / "build/Build/Products/Debug/DefenseClawMac.app"
fixture_name = "DefenseClawMacParityTest"
info_path = app_bundle / "Contents/Info.plist"
with info_path.open("rb") as handle:
    info = plistlib.load(handle)
original_binary = app_bundle / "Contents/MacOS" / info["CFBundleExecutable"]
fixture_binary = app_bundle / "Contents/MacOS" / fixture_name
if original_binary != fixture_binary:
    original_binary.rename(fixture_binary)
info["CFBundleExecutable"] = fixture_name
info["CFBundleName"] = fixture_name
info["CFBundleDisplayName"] = fixture_name
with info_path.open("wb") as handle:
    plistlib.dump(info, handle)
subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app_bundle)], check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

# Upgrade preparation rejects symlinked parent directories. Keep the disposable
# installation beneath the physical checkout, not macOS's /tmp or /var aliases.
fixture_parent = repo / "build/native-upgrade-fixtures"
fixture_parent.mkdir(parents=True, exist_ok=True)
server = subprocess.Popen([sys.executable, "-u", str(repo / "Tests/Support/parity_fixture.py"), "--serve"],
                          stdout=subprocess.PIPE, text=True,
                          env={**os.environ, "PARITY_FIXTURE_PARENT": str(fixture_parent)})
try:
    fixture = json.loads(server.stdout.readline())
    print("Fixture:", fixture, flush=True)
    fixture_root = Path(fixture["root"])
    env = {key: os.environ[key] for key in ("PATH", "HOME", "USER", "TMPDIR", "LANG", "LOGNAME") if key in os.environ}
    env.update(DEFENSECLAW_HOME=str(fixture_root), DEFENSECLAW_CONFIG=str(fixture_root / "config.yaml"),
               DEFENSECLAW_VENV=os.environ.get("DEFENSECLAW_TEST_VENV", str(repo.parent / "defenseclaw/.venv")), PYTHONDONTWRITEBYTECODE="1",
               PARITY_SCREENSHOTS=str(root / "screenshots"))
    if sys.argv[1:] == ["--run-runtime1010-gui"]:
        env["PARITY_RUNTIME1010_ONLY"] = "1"
    if sys.argv[1:] == ["--run-inspection-gui"]:
        env["PARITY_INSPECTION_ONLY"] = "1"
    if sys.argv[1:] == ["--run-sandbox-gui"]:
        env["PARITY_SANDBOX_ONLY"] = "1"
    if sys.argv[1:] in (["--run-upgrade-gui"], ["--run-opencode-upgrade-gui"]):
        env.update(PARITY_UPGRADE_ONLY="1", HOME=str(fixture_root), CFFIXED_USER_HOME=str(fixture_root),
                   DEFENSECLAW_HOME=str(fixture_root), DEFENSECLAW_CONFIG=str(fixture_root / "config.yaml"),
                   DEFENSECLAW_VENV=str(fixture_root / ".venv"))
    if sys.argv[1:] == ["--run-opencode-upgrade-gui"]:
        env["PARITY_OPENCODE_ONLY"] = "1"
    binary = fixture_binary
    args = [str(binary), "-defenseclawBinaryPath", str(fixture_root / "bin/defenseclaw"),
            "-startGatewayAutomatically", "NO", "-gatewayAdministratorMode", "NO",
            "-notifyCritical", "NO", "-notifyHigh", "NO", "-notifyGatewayOffline", "NO", "-notifySandboxEvents", "NO"]
    def press_fixture_button(pid, *, identifier=None, title=None):
        # Only this disposable process is targeted; never the installed app.
        predicate = (
            f'value of attribute "AXIdentifier" of itemRef is "{identifier}"'
            if identifier else f'name of itemRef is "{title}"'
        )
        script = f'''tell application "System Events"
            tell first application process whose unix id is {pid}
                repeat with w in windows
                    repeat with itemRef in entire contents of w
                        try
                            if role of itemRef is "AXButton" and {predicate} then
                                perform action "AXPress" of itemRef
                                return "pressed"
                            end if
                        end try
                    end repeat
                end repeat
            end tell
        end tell
        error "Fixture button was not found"'''
        result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, timeout=10)
        if result.returncode and identifier == "runtime-upgrade-stop-opencode":
            # Some macOS SwiftUI builds omit button identifiers from AX. The
            # native screenshot/source locates this control in the runtime section;
            # verify its text and two-button structure before using that fallback.
            fallback = f'''tell application "System Events"
                tell first application process whose unix id is {pid}
                    set runtimeSection to group 3 of scroll area 1 of group 1 of window 1
                    set messages to (get value of every static text of runtimeSection)
                    set messages to messages as text
                    if messages contains "OpenCode is still running" and (count of buttons of runtimeSection) is 2 then
                        click button 1 of runtimeSection
                        return "pressed"
                    end if
                end tell
            end tell
            error "Fixture runtime section changed"'''
            result = subprocess.run(["/usr/bin/osascript", "-e", fallback], capture_output=True, text=True, timeout=10)
        if result.returncode and title == "Cancel":
            # SwiftUI's cancel role also supports Escape when its button title is
            # omitted from AX. Focus only the distinct disposable application.
            fallback = f'''tell application "System Events"
                tell first application process whose unix id is {pid}
                    set frontmost to true
                    delay 0.2
                    key code 53
                end tell
            end tell'''
            result = subprocess.run(["/usr/bin/osascript", "-e", fallback], capture_output=True, text=True, timeout=10)
        if result.returncode and title in ("Review", "Apply Change"):
            # SwiftUI may omit native button names; use the form's default action
            # only in the exact disposable runtime-feature window.
            fallback = f'''tell application "System Events"
                tell first application process whose unix id is {pid}
                    if name of window 1 is not "Parity fixture: runtime1010-add-model" then error "Unexpected fixture window"
                    set frontmost to true
                    delay 0.2
                    key code 36
                end tell
            end tell'''
            result = subprocess.run(["/usr/bin/osascript", "-e", fallback], capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise RuntimeError("Native fixture accessibility action failed: " + result.stderr.strip())

    with (root / "run.log").open("w") as log:
        process = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 240
        dialog_open = False
        dialog_cancelled = False
        try:
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError("Native fixture timed out")
                for marker, title in [("runtime1010-review", "Review"), ("runtime1010-apply", "Apply Change")]:
                    if (fixture_root / (marker + "-ready")).exists() and not (fixture_root / (marker + "-done")).exists():
                        press_fixture_button(process.pid, title=title)
                        (fixture_root / (marker + "-done")).touch()
                if (fixture_root / "opencode-ui-ready").exists() and not dialog_open:
                    press_fixture_button(process.pid, identifier="runtime-upgrade-stop-opencode")
                    time.sleep(0.5)
                    (fixture_root / "opencode-dialog-open").touch()
                    dialog_open = True
                if (fixture_root / "opencode-dialog-captured").exists() and not dialog_cancelled:
                    press_fixture_button(process.pid, title="Cancel")
                    (fixture_root / "opencode-ui-cancelled").touch()
                    dialog_cancelled = True
                time.sleep(0.1)
            result = process
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    output = (root / "run.log").read_text()
    print(output)
    if result.returncode or "PASS all native panel/form renders completed" not in output:
        sys.exit(1)
finally:
    server.terminate()
    server.wait(timeout=10)
