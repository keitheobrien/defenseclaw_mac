#!/usr/bin/env python3
"""Opt-in integration: install a verified payload into a disposable macOS HOME."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) != 3 or sys.argv[1] != '--payload':
    raise SystemExit('Usage: test_runtime_fresh_install.py --payload /verified/RuntimePayload')
payload = Path(sys.argv[2]).resolve()
repo = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(repo / 'scripts/verify_runtime_payload.py'), str(payload)], check=True)
root = Path(tempfile.mkdtemp(prefix='defenseclawmac-fresh-', dir='/private/tmp'))
print('Disposable fresh-install artifacts:', root, flush=True)
source = root / 'source'
source.mkdir()
for name in ('DefenseClawMac', 'DefenseClawMac.xcodeproj', 'GatewayAdminHelper', 'script'):
    shutil.copytree(repo / name, source / name, ignore=shutil.ignore_patterns('__pycache__', 'xcuserdata'))
entry = source / 'DefenseClawMac/App/DefenseClawApp.swift'
entry.write_text(entry.read_text().replace('@main\nstruct DefenseClawApp', 'struct DefenseClawApp', 1))
shutil.copy2(repo / 'Tests/RuntimeFreshInstallTests.swift', source / 'DefenseClawMac/App/RuntimeFreshInstallTests.swift')
with (root / 'build.log').open('w') as log:
    subprocess.run(['xcodebuild', '-project', str(source / 'DefenseClawMac.xcodeproj'), '-scheme', 'DefenseClawMac',
                    '-configuration', 'Debug', '-destination', 'generic/platform=macOS', '-derivedDataPath', str(root / 'build'),
                    'CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES',
                    'PRODUCT_BUNDLE_IDENTIFIER=com.keitheobrien.DefenseClawMac.FreshInstallTest', 'build'], stdout=log, stderr=subprocess.STDOUT, check=True)
app = root / 'build/Build/Products/Debug/DefenseClawMac.app'
shutil.copytree(payload, app / 'Contents/Resources/RuntimePayload')
# Re-seal only the host. Nested release binaries retain their Developer ID signatures.
subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True)
# Match Foundation's canonical macOS temporary-home spelling.
home = Path(str(root / 'home').replace('/private/tmp/', '/tmp/', 1))
home.mkdir()
env = {key: os.environ[key] for key in ('TMPDIR', 'LANG', 'USER', 'LOGNAME') if key in os.environ}
env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), DC_TEST_HOME=str(home),
           PATH='/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin', DEFENSECLAW_HOME=str(home / '.defenseclaw'),
           DEFENSECLAW_VENV=str(home / '.defenseclaw/.venv'),
           UV_CACHE_DIR=str(root / 'uv-cache'), PYTHONDONTWRITEBYTECODE='1')
with (root / 'run.log').open('w') as log:
    result = subprocess.run([str(app / 'Contents/MacOS/DefenseClawMac'), '-startGatewayAutomatically', 'NO',
                             '-gatewayAdministratorMode', 'NO', '-defenseclawBinaryPath', str(home / '.local/bin/defenseclaw')],
                            env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600)
print((root / 'run.log').read_text())
raise SystemExit(result.returncode)
