#!/usr/bin/env python3
"""Audit DefenseClawMac against upstream mainline and an installed runtime."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


UPSTREAM_URL = "https://github.com/cisco-ai-defense/defenseclaw.git"
class Audit:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str]] = []
        self.failures = 0

    def pass_(self, message: str) -> None:
        self.rows.append(("PASS", message))

    def warn(self, message: str) -> None:
        self.rows.append(("WARN", message))

    def fail(self, message: str) -> None:
        self.rows.append(("FAIL", message))
        self.failures += 1

    def render(self) -> str:
        heading = "Compatibility audit passed" if not self.failures else "Compatibility audit failed"
        body = [f"# {heading}", ""]
        body.extend(f"- **{status}** {message}" for status, message in self.rows)
        return "\n".join(body) + "\n"


def run(argv: list[str], *, cwd: Path | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )


def git_revision(repo: Path) -> str:
    result = run(["git", "rev-parse", "HEAD"], cwd=repo)
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        str(path.relative_to(root)): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != ".DS_Store"
    }


def runtime_contract_hashes(root: Path) -> dict[str, str]:
    paths = (
        "cli/defenseclaw",
        "internal/gateway",
        "extensions/defenseclaw",
        "go.mod",
        "go.sum",
        "release/source-install-identity.json",
        "scripts/install.sh",
        "scripts/upgrade.sh",
    )
    tracked = run(["git", "ls-files", "-z", "--", *paths], cwd=root)
    if tracked.returncode != 0:
        return {}
    hashes: dict[str, str] = {}
    for relative in tracked.stdout.split("\0"):
        if not relative:
            continue
        candidate = root / relative
        if candidate.name == ".placeholder" or not candidate.is_file():
            continue
        hashes[relative] = sha256(candidate)
    return hashes


def load_registry(path: Path) -> tuple[tuple[object, ...], ...]:
    module = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in module.body:
        target = node.target if isinstance(node, ast.AnnAssign) else None
        if isinstance(target, ast.Name) and target.id == "GO_PARITY_REGISTRY":
            value = ast.literal_eval(node.value)
            if not isinstance(value, tuple):
                break
            return value
    raise ValueError(f"GO_PARITY_REGISTRY not found in {path}")


def swift_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def render_registry(entries: tuple[tuple[object, ...], ...]) -> str:
    lines = [
        f"    static let sourceCount = {len(entries)}",
        "    static let all: [CommandDefinition] = [",
    ]
    for index, row in enumerate(entries):
        if len(row) != 7:
            raise ValueError(f"registry row {index} has {len(row)} fields")
        title, binary, arguments, summary, category, requires_input, usage = row
        args = "[" + ", ".join(swift_string(str(arg)) for arg in arguments) + "]"
        lines.append(
            "        CommandDefinition("
            f"id: {index}, title: {swift_string(str(title))}, "
            f"binary: {swift_string(str(binary))}, arguments: {args}, "
            f"summary: {swift_string(str(summary))}, category: {swift_string(str(category))}, "
            f"requiresInput: {str(bool(requires_input)).lower()}, usage: {swift_string(str(usage))}),"
        )
    lines.append("    ]")
    return "\n".join(lines) + "\n"


def runtime_normalized_registry(
    entries: tuple[tuple[object, ...], ...]
) -> tuple[tuple[object, ...], ...]:
    """Correct source-registry hints that disagree with the executable CLI."""
    normalized = []
    for row in entries:
        if row[0] == "setup webhook add":
            row = (*row[:6], "<slack|pagerduty|webex|generic> [flags]")
        normalized.append(row)
    return tuple(normalized)


REGISTRY_BLOCK = re.compile(
    r"    static let sourceCount = \d+\n"
    r"    static let all: \[CommandDefinition\] = \[\n"
    r".*?^    \]\n",
    re.MULTILINE | re.DOTALL,
)


def check_registry(
    audit: Audit,
    swift_path: Path,
    registry_path: Path,
    *,
    sync: bool,
) -> None:
    entries = runtime_normalized_registry(load_registry(registry_path))
    expected = render_registry(entries)
    current = swift_path.read_text(encoding="utf-8")
    match = REGISTRY_BLOCK.search(current)
    if not match:
        audit.fail("Mac command registry block could not be parsed")
        return
    if match.group(0) == expected:
        audit.pass_(f"command palette matches all {len(entries)} upstream entries")
        return
    if not sync:
        audit.fail(
            f"command palette differs from the {len(entries)}-entry upstream registry; "
            "rerun with --sync-command-registry and inspect the diff"
        )
        return
    swift_path.write_text(current[: match.start()] + expected + current[match.end() :], encoding="utf-8")
    audit.pass_(f"synchronized command palette to {len(entries)} upstream entries")


def parse_upstream_version(upstream: Path) -> str:
    with (upstream / "pyproject.toml").open("rb") as handle:
        return str(tomllib.load(handle)["project"]["version"])


def parse_config_version(upstream: Path) -> int:
    text = (upstream / "cli/defenseclaw/migrations.py").read_text(encoding="utf-8")
    match = re.search(r"SUPPORTED_CONFIG_VERSIONS:\s*tuple\[int, \.\.\.\]\s*=\s*\(([^)]*)\)", text)
    if not match:
        raise ValueError("SUPPORTED_CONFIG_VERSIONS not found")
    versions = [int(value) for value in re.findall(r"\d+", match.group(1))]
    if not versions:
        raise ValueError("no supported config versions found")
    return max(versions)


def parse_app_version(mac_root: Path) -> str:
    text = (mac_root / "DefenseClawMac.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", text))
    return versions.pop() if len(versions) == 1 else "unknown"


def runtime_source_checkout(runtime: Path) -> Path | None:
    resolved = runtime.resolve()
    for parent in resolved.parents:
        if (parent / ".git").exists():
            return parent
    return None


def dependency_probe_mode(installed_version: str, source_version: str) -> str:
    return "upstream" if installed_version == source_version else "installed"


def has_shell_assignment(source: str, variable: str, value: str) -> bool:
    return bool(
        re.search(
            rf"(?m)^[ \t]*(?:export[ \t]+)?{re.escape(variable)}[ \t]*=[ \t]*"
            rf"{re.escape(value)}[ \t]*(?:#.*)?$",
            source,
        )
    )


def probe_runtime(
    audit: Audit,
    runtime: Path,
    upstream_version: str,
    upstream_commit: str,
    upstream: Path,
) -> None:
    version = run([str(runtime), "--version"])
    match = re.search(r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?", version.stdout)
    installed = match.group(0) if match else "unknown"
    if version.returncode != 0 or installed == "unknown":
        audit.fail(f"installed runtime version probe failed at {runtime}")
    elif installed != upstream_version:
        audit.warn(
            f"installed runtime {installed} differs from source metadata {upstream_version} "
            f"({runtime}); validating executable contracts and installed package metadata"
        )
    else:
        audit.pass_(f"installed runtime {installed} matches upstream ({runtime})")
    dependency_mode = dependency_probe_mode(installed, upstream_version)

    source_checkout = runtime_source_checkout(runtime)
    if source_checkout is not None:
        source_commit = git_revision(source_checkout)
        if source_commit == upstream_commit:
            audit.pass_(f"installed runtime source matches upstream commit ({source_checkout})")
        else:
            installed_contracts = runtime_contract_hashes(source_checkout)
            upstream_contracts = runtime_contract_hashes(upstream)
            changed = sorted(
                path
                for path in set(installed_contracts) | set(upstream_contracts)
                if installed_contracts.get(path) != upstream_contracts.get(path)
            )
            if changed:
                sample = ", ".join(changed[:8])
                suffix = " ..." if len(changed) > 8 else ""
                audit.fail(
                    f"installed runtime source {source_commit} differs from upstream "
                    f"{upstream_commit} in {len(changed)} contract file(s): {sample}{suffix}"
                )
            else:
                audit.pass_(
                    f"installed runtime contracts match upstream; source commit "
                    f"{source_commit} differs only outside runtime surfaces"
                )
        status = run(["git", "status", "--porcelain"], cwd=source_checkout)
        if status.returncode != 0:
            audit.warn(f"installed runtime source status could not be read ({source_checkout})")
        elif status.stdout.strip():
            audit.warn("installed runtime source checkout has local changes")

    probes = (
        (["setup", "observability", "--help"], ("add", "list", "enable", "disable", "remove", "test")),
        (["agent", "discovery", "enable", "--help"], ("--no-restart", "--no-scan")),
        (["setup", "provider", "add", "--help"], ("--base-url",)),
        (["setup", "webhook", "add", "--help"], ("<type>", "--url")),
    )
    for arguments, expected in probes:
        result = run([str(runtime), *arguments])
        label = " ".join(arguments[:-1])
        missing = [token for token in expected if token not in result.stdout]
        if result.returncode != 0 or missing:
            audit.fail(f"runtime help contract failed for {label}; missing {', '.join(missing) or 'command'}")
        else:
            audit.pass_(f"runtime help contract is available for {label}")

    resolved = runtime.resolve()
    python = resolved.parent / "python"
    upstream_dependency_script = r'''
import importlib.metadata
import json
import sys
from packaging.requirements import Requirement

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

with open(sys.argv[1], "rb") as handle:
    document = tomllib.load(handle)
dependencies = document["project"]["dependencies"]
overrides = document.get("tool", {}).get("uv", {}).get("override-dependencies", [])
effective = {}
for raw in dependencies:
    requirement = Requirement(raw)
    if requirement.marker is None or requirement.marker.evaluate():
        effective[requirement.name.lower()] = requirement
for raw in overrides:
    requirement = Requirement(raw)
    if requirement.marker is not None and not requirement.marker.evaluate():
        continue
    try:
        importlib.metadata.version(requirement.name)
    except importlib.metadata.PackageNotFoundError:
        continue
    effective[requirement.name.lower()] = requirement
issues = []
for requirement in effective.values():
    try:
        installed = importlib.metadata.version(requirement.name)
    except importlib.metadata.PackageNotFoundError:
        issues.append(f"{requirement.name} is not installed")
        continue
    if requirement.specifier and installed not in requirement.specifier:
        issues.append(f"{requirement.name} {installed} does not satisfy {requirement.specifier}")
print(json.dumps(issues))
'''
    installed_dependency_script = r'''
import importlib.metadata
import json
from packaging.requirements import Requirement

issues = []
for raw in importlib.metadata.requires("defenseclaw") or []:
    requirement = Requirement(raw)
    if requirement.marker is not None and not requirement.marker.evaluate():
        continue
    try:
        installed = importlib.metadata.version(requirement.name)
    except importlib.metadata.PackageNotFoundError:
        issues.append(f"{requirement.name} is not installed")
        continue
    if requirement.specifier and installed not in requirement.specifier:
        issues.append(f"{requirement.name} {installed} does not satisfy {requirement.specifier}")
print(json.dumps(issues))
'''
    dependencies = (
        run(
            [
                str(python),
                "-c",
                upstream_dependency_script if dependency_mode == "upstream" else installed_dependency_script,
                *([str(upstream / "pyproject.toml")] if dependency_mode == "upstream" else []),
            ]
        )
        if python.is_file()
        else None
    )
    if dependencies is None or dependencies.returncode != 0:
        audit.fail("installed runtime dependency set could not be compared with upstream")
    else:
        try:
            dependency_issues = json.loads(dependencies.stdout)
        except json.JSONDecodeError:
            dependency_issues = ["dependency probe returned invalid output"]
        if dependency_issues:
            audit.fail("installed runtime dependencies differ: " + "; ".join(dependency_issues))
        else:
            if dependency_mode == "upstream":
                audit.pass_("installed runtime dependencies satisfy upstream requirements")
            else:
                audit.pass_("installed runtime dependencies satisfy packaged runtime requirements")
                audit.warn("upstream resolver overrides were not compared across the source-version skew")

    catalog_script = (
        "from defenseclaw import config as c; "
        "from defenseclaw.tui.panels.setup import build_setup_sections; "
        "print(len(build_setup_sections(c.load())))"
    )
    catalog = run([str(python), "-c", catalog_script]) if python.is_file() else None
    if catalog is None or catalog.returncode != 0 or not catalog.stdout.strip().isdigit():
        audit.fail("runtime setup catalog could not be loaded through the selected CLI's venv")
    else:
        audit.pass_(f"runtime setup catalog exposes {catalog.stdout.strip()} sections")


def check_retired_surfaces(audit: Audit, mac_root: Path) -> None:
    checks = (
        (mac_root / "DefenseClawMac/Features/SetupDefinitions.swift", "--emit-otel", "removed --emit-otel flag"),
        (mac_root / "DefenseClawMac/Features/ConfigEditorDefinitions.swift", 'key: "otel.', "removed config-v7 otel.* editor field"),
        (mac_root / "DefenseClawMac/DataLayer/CommandRegistry.swift", "migrate-splunk", "removed migrate-splunk command"),
    )
    failures = []
    for path, needle, label in checks:
        if needle in path.read_text(encoding="utf-8"):
            failures.append(label)
    if failures:
        audit.fail("retired runtime surfaces remain: " + ", ".join(failures))
    else:
        audit.pass_("removed config-v7 flags, keys, and commands are absent")


def check_release_protocol(audit: Audit, mac_root: Path) -> None:
    script = mac_root / "scripts/build_unified_dmg.sh"
    if not script.is_file():
        audit.fail("combined installer script is missing")
        return
    syntax = run(["bash", "-n", str(script)], cwd=mac_root)
    if syntax.returncode != 0:
        audit.fail("combined installer script has invalid shell syntax")
        return
    source = script.read_text(encoding="utf-8")
    required = (
        "protocol2_darwin_${ARCH}.dcgateway",
        "-2-py3-none-any.dcwheel",
        "upgrade-manifest.json",
        "runtime-candidate-checksums.txt",
        '--certificate-identity "https://github.com/${RUNTIME_REPO}/.github/workflows/release.yaml@refs/heads/main"',
    )
    forbidden_assignments = {
        "TARBALL": '"$RUNTIME_DIR/defenseclaw_${RUNTIME_VERSION}_darwin_${ARCH}.tar.gz"',
        "WHEEL": '"$RUNTIME_DIR/defenseclaw-${RUNTIME_VERSION}-py3-none-any.whl"',
    }
    forbidden_tokens = ("--certificate-identity-regexp",)
    missing = [token for token in required if token not in source]
    stale = [
        f"{variable}={value}"
        for variable, value in forbidden_assignments.items()
        if has_shell_assignment(source, variable, value)
    ]
    stale.extend(token for token in forbidden_tokens if token in source)
    runtime_installer = (
        mac_root / "DefenseClawMac/DataLayer/RuntimeInstaller.swift"
    ).read_text(encoding="utf-8")
    if 'wheelFile == "defenseclaw-\\(version)-2-py3-none-any.dcwheel"' not in runtime_installer:
        missing.append("RuntimeInstaller protected-wheel requirement")
    if missing or stale:
        details = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if stale:
            details.append("retired " + ", ".join(stale))
        audit.fail("combined installer is not on the schema-2 release protocol: " + "; ".join(details))
    else:
        audit.pass_("combined installer uses signed schema-2 protected runtime artifacts")


def check_source_baseline(
    audit: Audit,
    mac_root: Path,
    upstream: Path,
    baseline_path: Path,
    metadata: dict[str, object],
    *,
    write_baseline: bool,
) -> None:
    local_root = mac_root / "DefenseClawMac"
    upstream_root = upstream / "macos/DefenseClawMac/DefenseClawMac"
    local_hashes = tree_hashes(local_root)
    upstream_hashes = tree_hashes(upstream_root)
    differences = {
        path: {
            "upstream_sha256": upstream_hashes.get(path, "missing"),
            "local_sha256": local_hashes.get(path, "missing"),
        }
        for path in sorted(set(local_hashes) | set(upstream_hashes))
        if local_hashes.get(path) != upstream_hashes.get(path)
    }

    if write_baseline:
        document = dict(metadata)
        document["intentional_source_differences"] = {
            path: {
                **hashes,
                "reason": "Reviewed standalone identity, retained standalone behavior, or compatibility hardening.",
            }
            for path, hashes in differences.items()
        }
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        audit.pass_(f"wrote reviewed baseline with {len(differences)} intentional source differences")
        return

    if not baseline_path.is_file():
        audit.fail("compatibility baseline is missing; review and create it with --write-baseline")
        return
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    if baseline.get("upstream_commit") != metadata["upstream_commit"]:
        audit.fail(
            f"upstream moved from {baseline.get('upstream_commit', 'unknown')} "
            f"to {metadata['upstream_commit']}; perform a fresh compatibility review"
        )
    expected = baseline.get("intentional_source_differences", {})
    # Compare only hashes while allowing human-edited reason text.
    changed = [
        path for path, hashes in differences.items()
        if any(expected.get(path, {}).get(key) != value for key, value in hashes.items())
    ]
    removed = sorted(set(expected) - set(differences))
    if changed:
        audit.fail("unreviewed source differences: " + ", ".join(changed))
    else:
        audit.pass_(f"{len(differences)} intentional source differences match reviewed hashes")
    if removed:
        audit.warn("baseline differences no longer present: " + ", ".join(removed))


def run_tests(audit: Audit, mac_root: Path) -> None:
    scripts = sorted((mac_root / "script").glob("test_*.sh"))
    if not scripts:
        audit.fail("no compatibility tests were found in script/")
        return
    for script in scripts:
        name = script.name
        result = run([str(script)], cwd=mac_root, timeout=180)
        if result.returncode == 0:
            audit.pass_(f"script/{name}")
        else:
            tail = " | ".join(result.stdout.strip().splitlines()[-3:])
            audit.fail(f"script/{name}: {tail}")


def build_app(audit: Audit, mac_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="defenseclaw-mac-compat-build.") as derived:
        result = run(
            [
                "xcodebuild",
                "-project", "DefenseClawMac.xcodeproj",
                "-scheme", "DefenseClawMac",
                "-configuration", "Debug",
                "-derivedDataPath", derived,
                "CODE_SIGN_STYLE=Manual",
                "CODE_SIGN_IDENTITY=-",
                "DEVELOPMENT_TEAM=",
                "build",
            ],
            cwd=mac_root,
            timeout=600,
        )
        if result.returncode == 0:
            audit.pass_("Debug macOS build succeeded")
        else:
            tail = " | ".join(result.stdout.strip().splitlines()[-8:])
            audit.fail(f"Debug macOS build failed: {tail}")


def resolve_upstream(path: str | None) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    if path:
        return Path(path).expanduser().resolve(), None
    temporary = tempfile.TemporaryDirectory(prefix="defenseclaw-mainline.")
    clone = run(["git", "clone", "--depth", "1", "--branch", "main", UPSTREAM_URL, temporary.name], timeout=300)
    if clone.returncode != 0:
        temporary.cleanup()
        raise RuntimeError("could not clone upstream: " + clone.stdout.strip())
    return Path(temporary.name), temporary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac-root", default=".")
    parser.add_argument("--upstream", help="current cisco-ai-defense/defenseclaw checkout")
    parser.add_argument("--runtime-bin", help="installed defenseclaw executable")
    parser.add_argument("--sync-command-registry", action="store_true")
    parser.add_argument("--run-tests", action="store_true")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--report", help="also write the Markdown report to this path")
    args = parser.parse_args()

    audit = Audit()
    mac_root = Path(args.mac_root).expanduser().resolve()
    baseline_path = Path(__file__).resolve().parent.parent / "references/compatibility-baseline.json"
    temporary: tempfile.TemporaryDirectory[str] | None = None
    try:
        upstream, temporary = resolve_upstream(args.upstream)
        upstream_sha = git_revision(upstream)
        upstream_version = parse_upstream_version(upstream)
        config_version = parse_config_version(upstream)
        app_version = parse_app_version(mac_root)
        audit.pass_(f"upstream mainline {upstream_sha} reports runtime {upstream_version}")
        audit.pass_(f"upstream supports config_version {config_version}; Mac app version is {app_version}")

        registry_path = upstream / "cli/defenseclaw/tui/registry_data.py"
        swift_registry = mac_root / "DefenseClawMac/DataLayer/CommandRegistry.swift"
        check_registry(audit, swift_registry, registry_path, sync=args.sync_command_registry)
        check_retired_surfaces(audit, mac_root)
        check_release_protocol(audit, mac_root)

        runtime_text = args.runtime_bin or shutil.which("defenseclaw")
        if runtime_text:
            probe_runtime(
                audit,
                Path(runtime_text).expanduser(),
                upstream_version,
                upstream_sha,
                upstream,
            )
        else:
            audit.fail("no installed defenseclaw executable was found")

        metadata: dict[str, object] = {
            "upstream_commit": upstream_sha,
            "runtime_version": upstream_version,
            "config_version": config_version,
            "mac_app_version": app_version,
        }
        check_source_baseline(
            audit,
            mac_root,
            upstream,
            baseline_path,
            metadata,
            write_baseline=args.write_baseline,
        )
        if args.run_tests:
            run_tests(audit, mac_root)
        if args.build:
            build_app(audit, mac_root)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        audit.fail(str(error))
    finally:
        if temporary is not None:
            temporary.cleanup()

    report = audit.render()
    print(report, end="")
    if args.report:
        Path(args.report).expanduser().write_text(report, encoding="utf-8")
    return 1 if audit.failures else 0


if __name__ == "__main__":
    sys.exit(main())
