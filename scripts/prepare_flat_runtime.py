#!/usr/bin/env python3
"""Prepare the authenticated 1.x release inputs; never resolve dependencies anew."""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from urllib.parse import urlsplit

SIGNER = 'https://github.com/cisco-ai-defense/defenseclaw/.github/workflows/release.yaml@refs/heads/main'
ISSUER = 'https://token.actions.githubusercontent.com'
TEAM = '9R236BB67S'
IDENTITY = f'Developer ID Application: Keith OBrien ({TEAM})'


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def checksum_entries(path: Path) -> dict[str, str]:
    entries = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  \*?([^/\\\s]+)', line)
        if not match or match[2] in entries:
            raise ValueError('Invalid or duplicate release checksum')
        entries[match[2]] = match[1]
    return entries


def validate_requirements(path: Path) -> None:
    # Environment markers belong to the upstream universal lock. uv evaluates
    # them for the selected Python/platform; only signed, pinned rows are used.
    rows = 0
    hashes = 0
    for raw in path.read_text().splitlines():
        line = raw.strip().removesuffix('\\').strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('--hash=sha256:'):
            if not re.fullmatch(r'--hash=sha256:[0-9a-f]{64}', line):
                raise ValueError('Invalid dependency hash')
            hashes += 1
            continue
        if rows and not hashes:
            raise ValueError('Unhashed dependency')
        hashes = 0
        head = line.split(';', 1)[0].strip()
        if ' @ ' in head:
            name, url = head.split(' @ ', 1)
            parsed = urlsplit(url)
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or parsed.scheme != 'https' or parsed.hostname != 'files.pythonhosted.org' or parsed.username or parsed.password or parsed.port not in (None, 443):
                raise ValueError('Untrusted direct dependency')
        elif not re.fullmatch(r'[A-Za-z0-9_.-]+(?:\[[A-Za-z0-9_,.-]+\])?==[A-Za-z0-9_.+!-]+', head):
            raise ValueError('Dependency is not exactly pinned')
        rows += 1
    if not rows or not hashes:
        raise ValueError('Empty or unhashed dependency lock')


def extract_binaries(archive: Path, destination: Path) -> None:
    names = {'defenseclaw-gateway', 'defenseclaw-acp'}
    found = set()
    with tarfile.open(archive, 'r:gz') as source:
        for member in source:
            if member.name not in names:
                continue
            if member.name in found or not member.isfile() or not 0 < member.size <= 512 * 1024 * 1024:
                raise ValueError('Unsafe or duplicate runtime executable')
            found.add(member.name)
            stream = source.extractfile(member)
            if stream is None:
                raise ValueError('Runtime executable missing')
            with stream, (destination / member.name).open('xb') as output:
                shutil.copyfileobj(stream, output)
            (destination / member.name).chmod(0o755)
    if found != names:
        raise ValueError('Release must include both gateway and ACP executables')


def source_commit(bundle: Path, work: Path) -> str:
    # Called only after cosign verifies this exact bundle/checksum pair.
    data = json.loads(bundle.read_text())
    if 'cert' in data:
        certificate = base64.b64decode(data['cert'], validate=True)
        form = 'PEM' if certificate.startswith(b'-----BEGIN CERTIFICATE') else 'DER'
    else:
        material = data['verificationMaterial']
        cert = material.get('certificate') or material['x509CertificateChain']['certificates'][0]
        certificate = base64.b64decode(cert['rawBytes'], validate=True)
        form = 'DER'
    path = work / 'release-certificate'
    path.write_bytes(certificate)
    text = subprocess.check_output(['openssl', 'x509', '-inform', form, '-in', str(path), '-noout', '-text'], text=True)
    # Fulcio Source Repository Digest extension, not an unauthenticated tag.
    match = re.search(r'1\.3\.6\.1\.4\.1\.57264\.1\.13:\s*\n[^\n]*?([0-9a-f]{40})\s*\n', text)
    if not match:
        raise ValueError('Verified signing certificate has no source commit')
    return match[1]


def prepare(version: str, work: Path, assets: Path | None = None) -> None:
    if not re.fullmatch(r'1\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', version):
        raise ValueError('Only the reviewed 1.x flat release protocol is supported')
    work.mkdir(parents=True, exist_ok=True)
    names = ['checksums.txt', 'checksums.txt.bundle', f'defenseclaw-{version}-darwin-arm64.tar.gz',
             f'defenseclaw-{version}-py3-none-any.whl', f'defenseclaw-{version}-requirements.txt', 'install.sh']
    if assets:
        for name in names:
            shutil.copyfile(assets / name, work / name)
    else:
        command = ['gh', 'release', 'download', version, '--repo', 'cisco-ai-defense/defenseclaw', '--dir', str(work)]
        for name in names:
            command.extend(['--pattern', name])
        subprocess.run(command, check=True)
    subprocess.run(['cosign', 'verify-blob', '--bundle', str(work / 'checksums.txt.bundle'),
                    '--certificate-identity', SIGNER, '--certificate-oidc-issuer', ISSUER,
                    str(work / 'checksums.txt')], check=True)
    checksums = checksum_entries(work / 'checksums.txt')
    for name in names[2:]:
        if digest(work / name) != checksums.get(name):
            raise ValueError(f'Release checksum mismatch: {name}')
    commit = source_commit(work / 'checksums.txt.bundle', work)
    validate_requirements(work / names[4])
    extract_binaries(work / names[2], work)
    payload = work / 'prepared-payload'
    payload.mkdir()
    manifest = dict(schema_version=3, runtime_version=version, runtime_tag=version, arch='arm64',
                    runtime_source=dict(commit=commit), release_archive=dict(file=names[2], sha256=checksums[names[2]]))
    for key, name, identifier in [('gateway', 'defenseclaw-gateway', 'com.cisco.defenseclaw.gateway'),
                                  ('acp_guard', 'defenseclaw-acp', 'com.cisco.defenseclaw.acp')]:
        path = work / name
        upstream_sha = digest(path)
        subprocess.run(['/usr/bin/codesign', '-f', '-o', 'runtime', '--timestamp', '--identifier', identifier, '-s', IDENTITY, str(path)], check=True)
        requirement = f'=anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{TEAM}"'
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', requirement, str(path)], check=True)
        reported = subprocess.check_output([str(path), '--version'], text=True).strip()
        if not re.search(r'(?<![\w.])' + re.escape(version) + r'(?![\w.])', reported):
            raise ValueError(f'Unexpected {name} version: {reported}')
        shutil.copyfile(path, payload / name)
        (payload / name).chmod(0o755)
        manifest[key] = dict(file=name, sha256=digest(path), upstream_sha256=upstream_sha)
    for key, source, name in [('wheel', names[3], names[3]), ('dependency_lock', names[4], 'runtime-requirements.lock'),
                              ('installer', 'install.sh', 'install.sh'), ('runtime_attestation', 'checksums.txt', 'runtime-candidate-checksums.txt'),
                              ('signature_bundle', 'checksums.txt.bundle', 'checksums.txt.bundle')]:
        shutil.copyfile(work / source, payload / name)
        manifest[key] = dict(file=name, sha256=digest(payload / name))
    (payload / 'VERSION').write_text(version + '\n')
    manifest['version_file'] = dict(file='VERSION', sha256=digest(payload / 'VERSION'))
    (payload / 'payload-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print(f'Authenticated flat runtime {version}, source {commit}; gateway and ACP signed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('version')
    parser.add_argument('work', type=Path)
    parser.add_argument('--assets', type=Path)
    args = parser.parse_args()
    prepare(args.version, args.work, args.assets)
