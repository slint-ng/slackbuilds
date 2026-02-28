#!/usr/bin/env python3
import argparse
import shutil
import subprocess
from pathlib import Path

from convert_slackbuild import audit_existing_package_dir


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


def audit_package_dir(pkg_dir: Path, run_shellcheck: bool) -> list[str]:
    issues = audit_existing_package_dir(pkg_dir)
    slkbuild_path = pkg_dir / 'SLKBUILD'
    if not slkbuild_path.exists():
        return issues

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
    parser = argparse.ArgumentParser(description='Check conversion gates for package directories')
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
