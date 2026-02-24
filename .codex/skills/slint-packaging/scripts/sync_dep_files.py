#!/usr/bin/env python3
"""Create or update <pkgname>.dep files from depends= in tracked SLKBUILD files."""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
from pathlib import Path


def find_repo_root(start_path: Path) -> Path:
    current_path = start_path.resolve()
    for candidate_path in (current_path, *current_path.parents):
        if (candidate_path / ".git").exists():
            return candidate_path
    raise RuntimeError(f"Could not find git repository from {start_path}")


def list_tracked_slkbuilds(repo_root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "ls-files"],
        check=True,
        capture_output=True,
        text=True,
    )

    slkbuild_paths = []
    for relative_path in result.stdout.splitlines():
        if not relative_path.endswith("SLKBUILD"):
            continue
        path_obj = Path(relative_path)
        if path_obj.parts and path_obj.parts[0].startswith("."):
            continue
        if "templates" in path_obj.parts:
            continue
        slkbuild_paths.append(repo_root / path_obj)

    return sorted(slkbuild_paths)


def parse_assignment(raw_text: str, name: str) -> str | None:
    lines = raw_text.splitlines()
    assignment_pattern = re.compile(rf"^{re.escape(name)}\s*=(.*)$")

    for line_index, raw_line in enumerate(lines):
        match = assignment_pattern.match(raw_line)
        if not match:
            continue

        rhs_value = match.group(1).strip()
        if not rhs_value.startswith("("):
            return rhs_value

        block_lines = [rhs_value]
        balance_value = rhs_value.count("(") - rhs_value.count(")")
        current_index = line_index
        while balance_value > 0 and current_index + 1 < len(lines):
            current_index += 1
            next_line = lines[current_index].strip()
            block_lines.append(next_line)
            balance_value += next_line.count("(") - next_line.count(")")
        return "\n".join(block_lines)

    return None


def parse_tokens(raw_value: str) -> list[str]:
    if not raw_value:
        return []

    value_text = raw_value.strip()
    if value_text.startswith("("):
        end_index = value_text.rfind(")")
        if end_index >= 0:
            value_text = value_text[1:end_index]
        else:
            value_text = value_text[1:]

    try:
        token_list = shlex.split(value_text, comments=True, posix=True)
    except ValueError:
        token_list = [part.strip("'\"") for part in value_text.split()]

    clean_tokens = []
    seen_tokens = set()
    for token in token_list:
        token = token.strip()
        if not token:
            continue
        if token in {"(", ")", "\\"}:
            continue
        if token in seen_tokens:
            continue
        seen_tokens.add(token)
        clean_tokens.append(token)
    return clean_tokens


def parse_pkgname(raw_text: str, fallback_path: Path) -> str:
    pkg_value = parse_assignment(raw_text, "pkgname")
    if not pkg_value:
        return fallback_path.parent.name

    pkg_tokens = parse_tokens(pkg_value)
    if not pkg_tokens:
        return fallback_path.parent.name

    pkg_name = pkg_tokens[0]
    if "$" in pkg_name:
        return fallback_path.parent.name
    return pkg_name


def parse_depends(raw_text: str) -> list[str]:
    depends_value = parse_assignment(raw_text, "depends")
    if depends_value is None:
        return []
    return [token for token in parse_tokens(depends_value) if token != "python"]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync <pkgname>.dep files from depends= entries in tracked SLKBUILD files."
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Path to slackbuilds repository root (default: current directory).",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write/update dep files. Without this flag, run in check mode.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Explicit check mode (default behavior).",
    )
    args = parser.parse_args()

    if args.write and args.check:
        parser.error("--check and --write are mutually exclusive")

    repo_root = find_repo_root(Path(args.repo_root))
    slkbuild_paths = list_tracked_slkbuilds(repo_root)

    generated_count = 0
    unchanged_count = 0
    missing_count = 0
    changed_paths = []

    for slkbuild_path in slkbuild_paths:
        raw_text = slkbuild_path.read_text(encoding="utf-8", errors="replace")
        pkg_name = parse_pkgname(raw_text, slkbuild_path)
        depends_list = parse_depends(raw_text)
        dep_line = ",".join(depends_list)

        dep_path = slkbuild_path.parent / f"{pkg_name}.dep"
        expected_text = dep_line + "\n"

        if dep_path.exists():
            current_text = dep_path.read_text(encoding="utf-8", errors="replace")
            if current_text == expected_text:
                unchanged_count += 1
                continue
        else:
            missing_count += 1

        changed_paths.append(dep_path)
        if args.write:
            dep_path.write_text(expected_text, encoding="utf-8")
            generated_count += 1

    mode_text = "WRITE" if args.write else "CHECK"
    print(f"Mode: {mode_text}")
    print(f"Repository: {repo_root}")
    print(f"Tracked SLKBUILD files scanned: {len(slkbuild_paths)}")
    print(f"Dep files already matching: {unchanged_count}")
    print(f"Dep files missing before run: {missing_count}")
    print(f"Dep files needing update/create: {len(changed_paths)}")
    if args.write:
        print(f"Dep files written: {generated_count}")
    else:
        print("Run with --write to apply changes.")

    if changed_paths:
        print("Changed candidates:")
        for dep_path in changed_paths:
            print(dep_path.relative_to(repo_root))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
