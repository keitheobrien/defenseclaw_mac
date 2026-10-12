#!/usr/bin/env python3
"""Verify every sealed payload component and the upstream 1.x attestation."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from prepare_flat_runtime import SIGNER, ISSUER, TEAM, digest, checksum_entries, source_commit, validate_requirements


def verify(payload):
    manifest = json.loads((payload / 'payload-manifest.json').read_text())
    for key, item in manifest.items():
        if not isinstance(item, dict) or 'file' not in item or key == 'release_archive':
            continue
        name = item['file']
        if not isinstance(name, str) or Path(name).name != name or name in ('.', '..'):
            raise ValueError(f'Unsafe payload filename: {key}')
        path = payload / name
        if path.is_symlink() or not path.is_file() or digest(path) != item.get('sha256'):
            raise ValueError(f'Payload hash mismatch: {key}')
    if manifest.get('schema_version') != 3:
        return  # Legacy protocol is checked by its existing packaging gates.
    version = manifest['runtime_version']
    if not re.fullmatch(r'1\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version) or manifest['runtime_tag'] != version or manifest['arch'] != 'arm64':
        raise ValueError('Invalid flat payload identity')
    names = {'gateway': 'defenseclaw-gateway', 'acp_guard': 'defenseclaw-acp',
             'wheel': f'defenseclaw-{version}-py3-none-any.whl', 'dependency_lock': 'runtime-requirements.lock',
             'installer': 'install.sh', 'version_file': 'VERSION',
             'runtime_attestation': 'runtime-candidate-checksums.txt', 'signature_bundle': 'checksums.txt.bundle'}
    for key, name in names.items():
        if manifest[key]['file'] != name:
            raise ValueError(f'Unexpected payload component: {key}')
    subprocess.run(['cosign', 'verify-blob', '--bundle', str(payload / names['signature_bundle']),
                    '--certificate-identity', SIGNER, '--certificate-oidc-issuer', ISSUER,
                    str(payload / names['runtime_attestation'])], check=True)
    with tempfile.TemporaryDirectory() as work:
        commit = source_commit(payload / names['signature_bundle'], Path(work))
    if commit != manifest['runtime_source']['commit']:
        raise ValueError('Release source does not match verified certificate')
    checksums = checksum_entries(payload / names['runtime_attestation'])
    for key, upstream_name in [('wheel', names['wheel']), ('installer', 'install.sh'),
                               ('dependency_lock', f'defenseclaw-{version}-requirements.txt'),
                               ('release_archive', f'defenseclaw-{version}-darwin-arm64.tar.gz')]:
        if manifest[key]['sha256'] != checksums.get(upstream_name):
            raise ValueError(f'Upstream attestation mismatch: {key}')
    validate_requirements(payload / names['dependency_lock'])
    if (payload / 'VERSION').read_text() != version + '\n':
        raise ValueError('Runtime VERSION marker mismatch')
    for key, identifier in [('gateway', 'com.cisco.defenseclaw.gateway'), ('acp_guard', 'com.cisco.defenseclaw.acp')]:
        binary = payload / names[key]
        requirement = f'=anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{TEAM}"'
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', requirement, str(binary)], check=True)
        reported = subprocess.check_output([str(binary), '--version'], text=True).strip()
        if not re.search(r'(?<![\w.])' + re.escape(version) + r'(?![\w.])', reported):
            raise ValueError(f'Unexpected {key} version')
    print(f'Verified complete runtime {version} payload, source {commit}')

if __name__ == '__main__':
    verify(Path(sys.argv[1]))
