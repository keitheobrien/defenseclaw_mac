#!/usr/bin/env python3
"""Validate a generated runtime lock against authenticated source metadata."""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path
from urllib.parse import urlsplit

MAX_INPUT_BYTES = 8 * 1024 * 1024
HASH_PATTERN = re.compile(r"--hash=sha256:([0-9a-f]{64})(?:[ \\]*)$")
FRAGMENT_PATTERN = re.compile(r"sha256=([0-9a-f]{64})")
DIRECT_PATTERN = re.compile(
    r"^([A-Za-z0-9_.-]+)(?:\[[^]]+\])?[ \t]+@[ \t]+([^; \t]+)"
    r"(?:[ \t]*;[ \t]*(.+))?$"
)
NAMED_PATTERN = re.compile(r"^([A-Za-z0-9_.-]+)(?:\[[^]]+\])?[ \t]*(?:===|==|~=|>=|<=|!=|>|<).+$")
MARKER_CLAUSE = re.compile(
    r"^(python_version|python_full_version|sys_platform|platform_machine)"
    r"[ \t]*(==|!=|>=|<=|>|<)[ \t]*['\"]([^'\"]+)['\"]$"
)
TARGET_VALUES = {
    "python_full_version": "3.12.0",
    "python_version": "3.12",
    "sys_platform": "darwin",
    "platform_machine": "arm64",
}


def fail(message: str) -> None:
    raise SystemExit(message)


def read_bounded(path: Path) -> str:
    if not path.is_file() or path.stat().st_size > MAX_INPUT_BYTES:
        fail(f"invalid or oversized dependency input: {path.name}")
    return path.read_text(encoding="utf-8")


def canonicalize_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def marker_applies(marker: str | None) -> bool | None:
    if marker is None:
        return True
    result = True
    for raw_clause in re.split(r"[ \t]+and[ \t]+", marker):
        clause = MARKER_CLAUSE.fullmatch(raw_clause.strip())
        if clause is None:
            return None
        variable, operator, expected = clause.groups()
        actual = TARGET_VALUES[variable]
        if variable.startswith("python_"):
            actual_value = tuple(int(part) for part in actual.split("."))
            expected_value = tuple(int(part) for part in expected.split("."))
        else:
            actual_value = actual
            expected_value = expected
        comparison = (actual_value > expected_value) - (actual_value < expected_value)
        applies = {
            "==": comparison == 0,
            "!=": comparison != 0,
            ">=": comparison >= 0,
            "<=": comparison <= 0,
            ">": comparison > 0,
            "<": comparison < 0,
        }[operator]
        result = result and applies
    return result


def authenticated_direct_requirements(
    pyproject_path: Path,
) -> tuple[dict[str, tuple[str, str]], set[str]]:
    document = tomllib.loads(read_bounded(pyproject_path))
    requirements = list(document.get("project", {}).get("dependencies", []))
    requirements.extend(
        document.get("tool", {}).get("uv", {}).get("override-dependencies", [])
    )
    direct: dict[str, tuple[str, str]] = {}
    required: set[str] = set()
    for raw in requirements:
        if " @ " not in raw:
            continue
        match = DIRECT_PATTERN.fullmatch(raw.strip())
        if match is None:
            fail("authenticated source contains an invalid direct requirement")
        requirement_name, requirement_url, marker = match.groups()
        applies = marker_applies(marker)
        if applies is False:
            continue
        parsed = urlsplit(requirement_url)
        fragment = FRAGMENT_PATTERN.fullmatch(parsed.fragment)
        if (
            parsed.scheme != "https"
            or parsed.hostname != "files.pythonhosted.org"
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port is not None
            or parsed.query
            or not parsed.path.endswith(".whl")
            or fragment is None
        ):
            fail(f"authenticated source contains an unsafe direct reference for {requirement_name}")
        name = canonicalize_name(requirement_name)
        value = (requirement_url, fragment.group(1))
        if name in direct and direct[name] != value:
            fail(f"authenticated source has conflicting direct references for {requirement_name}")
        direct[name] = value
        if applies is True:
            required.add(name)
    return direct, required


def requirement_stanzas(lock_text: str) -> list[list[str]]:
    stanzas: list[list[str]] = []
    current: list[str] = []
    for raw in lock_text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            if current:
                stanzas.append(current)
                current = []
            continue
        if raw[:1].isspace():
            if not current:
                fail("dependency lock has an orphaned continuation line")
            current.append(raw.strip())
            continue
        if current:
            stanzas.append(current)
        current = [raw.strip()]
    if current:
        stanzas.append(current)
    return stanzas


def validate_lock(pyproject_path: Path, lock_path: Path) -> int:
    expected_direct, required_direct = authenticated_direct_requirements(pyproject_path)
    lock_text = read_bounded(lock_path)
    seen_direct: set[str] = set()
    count = 0
    for stanza in requirement_stanzas(lock_text):
        head = stanza[0].removesuffix("\\").rstrip()
        if head.startswith("-"):
            fail("dependency lock contains an index or installer directive")
        direct_match = DIRECT_PATTERN.fullmatch(head)
        named_match = NAMED_PATTERN.fullmatch(head)
        if direct_match is not None:
            requirement_name, requirement_url, marker = direct_match.groups()
            if marker is not None:
                fail("resolved dependency lock unexpectedly contains an environment marker")
        elif named_match is not None:
            requirement_name = named_match.group(1)
            requirement_url = None
        else:
            fail("dependency lock contains an invalid requirement")
        hashes = {
            match.group(1)
            for line in stanza[1:]
            if (match := HASH_PATTERN.fullmatch(line)) is not None
        }
        if not hashes:
            fail(f"dependency lock entry has no SHA-256 hash: {requirement_name}")
        count += 1
        if requirement_url is None:
            continue
        name = canonicalize_name(requirement_name)
        authenticated = expected_direct.get(name)
        if authenticated is None or requirement_url != authenticated[0]:
            fail(f"dependency lock contains an unauthenticated direct reference: {requirement_name}")
        if authenticated[1] not in hashes:
            fail(f"dependency lock direct-reference hash does not match source: {requirement_name}")
        seen_direct.add(name)
    missing = sorted(required_direct - seen_direct)
    if missing:
        fail("dependency lock omitted authenticated direct references: " + ", ".join(missing))
    return count


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: validate_dependency_lock.py <pyproject.toml> <requirements.lock>")
    count = validate_lock(Path(sys.argv[1]), Path(sys.argv[2]))
    print(f"    validated {count} hash-locked dependencies and authenticated direct references")
    return 0


if __name__ == "__main__":
    sys.exit(main())
