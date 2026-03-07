#!/usr/bin/env python3
import argparse
import shutil
import subprocess
from pathlib import Path

from check_slackdesc_len import extract_slackdesc_lines
from convert_slackbuild import audit_existing_package_dir

SLACKDESC_CHAR_LIMIT = 70
SLACKDESC_MAX_LINES = 10


def run_command(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    output = '\n'.join(part for part in (completed.stdout.strip(), completed.stderr.strip()) if part)
    return completed.returncode, output


def format_command_failure(label: str, output: str) -> list[str]:
    issues = [f"{label} failed"]
    if output:
        for line in output.splitlines():
            issues.append(f"{label}: {line}")
    return issues


def audit_slackdesc_limits(slkbuild_path: Path) -> list[str]:
    text = slkbuild_path.read_text(encoding='utf-8', errors='replace')
    slackdesc_lines = list(extract_slackdesc_lines(text))
    if not slackdesc_lines:
        return []

    issues = []
    if len(slackdesc_lines) > SLACKDESC_MAX_LINES:
        issues.append(
            f"slackdesc has {len(slackdesc_lines)} lines (max {SLACKDESC_MAX_LINES})"
        )

    for idx, line in enumerate(slackdesc_lines, 1):
        if '://' in line:
            continue
        if len(line) > SLACKDESC_CHAR_LIMIT:
            issues.append(
                f"slackdesc line {idx} has {len(line)} chars (max {SLACKDESC_CHAR_LIMIT})"
            )
    return issues


def audit_package_dir(pkg_dir: Path, run_shellcheck: bool) -> list[str]:
    issues = audit_existing_package_dir(pkg_dir)
    slkbuild_path = pkg_dir / 'SLKBUILD'
    if not slkbuild_path.exists():
        return issues

    issues.extend(audit_slackdesc_limits(slkbuild_path))

    bash_rc, bash_output = run_command(['bash', '-n', str(slkbuild_path)])
    if bash_rc != 0:
        issues.extend(format_command_failure('bash -n', bash_output))

    if run_shellcheck:
        shellcheck = shutil.which('shellcheck')
        if shellcheck is None:
            issues.append('`--shellcheck` requested but `shellcheck` is not installed')
        else:
            shellcheck_rc, shellcheck_output = run_command([shellcheck, str(slkbuild_path)])
            if shellcheck_rc != 0:
                issues.extend(format_command_failure('shellcheck', shellcheck_output))

    return issues


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Check conversion gates for package directories (markers, slackdesc, bash -n)'
    )
    parser.add_argument('package_dirs', nargs='+', help='Package directories to inspect')
    parser.add_argument('--shellcheck', action='store_true', help='Run shellcheck in addition to bash -n')
    args = parser.parse_args()

    failed = False
    for package_dir in args.package_dirs:
        pkg_dir = Path(package_dir).resolve()
        print(f"== {pkg_dir} ==")
        if not pkg_dir.is_dir():
            print("FAIL: not a directory")
            failed = True
            continue

        issues = audit_package_dir(pkg_dir, args.shellcheck)
        if issues:
            failed = True
            for issue in issues:
                print(f"FAIL: {issue}")
        else:
            print("OK")

    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
