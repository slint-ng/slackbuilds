#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


assignmentPattern = re.compile(
    r"^(?P<prefix>\s*(?:export\s+)?(?P<name>pkgver|pkgrel)\s*=\s*)(?P<value>.+?)(?P<suffix>\s*)$",
    re.MULTILINE,
)
quotedValuePattern = re.compile(r"""^(["'])(.*)\1$""")
numericPrefixPattern = re.compile(r"^(?P<number>\d+)(?P<suffix>.*)$")


def run_git(args: list[str], repoRoot: Path) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repoRoot,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git command failed")
    return result.stdout


def parse_assignment(content: str, variableName: str) -> tuple[str, re.Match[str]]:
    for match in assignmentPattern.finditer(content):
        if match.group("name") != variableName:
            continue
        rawValue = match.group("value").strip()
        quotedMatch = quotedValuePattern.match(rawValue)
        if quotedMatch:
            return quotedMatch.group(2), match
        return rawValue, match
    raise ValueError(f"missing {variableName}")


def bump_pkgrel(pkgrelValue: str) -> str:
    numericMatch = numericPrefixPattern.match(pkgrelValue)
    if not numericMatch:
        raise ValueError(f"pkgrel does not start with a number: {pkgrelValue}")
    bumpedNumber = int(numericMatch.group("number")) + 1
    return f"{bumpedNumber}{numericMatch.group('suffix')}"


def update_pkgrel(content: str, newPkgrel: str) -> str:
    updated = False

    def replacer(match: re.Match[str]) -> str:
        nonlocal updated
        if updated or match.group("name") != "pkgrel":
            return match.group(0)
        updated = True
        rawValue = match.group("value").strip()
        quoteChar = ""
        quotedMatch = quotedValuePattern.match(rawValue)
        if quotedMatch:
            quoteChar = quotedMatch.group(1)
        return f"{match.group('prefix')}{quoteChar}{newPkgrel}{quoteChar}{match.group('suffix')}"

    updatedContent = assignmentPattern.sub(replacer, content)
    if not updated:
        raise ValueError("could not update pkgrel")
    return updatedContent


def list_slkbuilds(repoRoot: Path, changedOnly: bool, baseRef: str) -> list[str]:
    if changedOnly:
        output = run_git(
            ["diff", "--name-only", "--diff-filter=ACMR", f"{baseRef}...HEAD", "--", "**/SLKBUILD"],
            repoRoot,
        )
        return [line for line in output.splitlines() if line.endswith("/SLKBUILD")]

    output = run_git(["ls-files", "*/*/SLKBUILD"], repoRoot)
    return [line for line in output.splitlines() if line.endswith("/SLKBUILD")]


def file_exists_in_ref(refName: str, filePath: str, repoRoot: Path) -> bool:
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{refName}:{filePath}"],
        cwd=repoRoot,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Bump pkgrel for changed SLKBUILDs whose pkgver and pkgrel still "
            "match the chosen base branch."
        )
    )
    parser.add_argument("--base-ref", default="origin/main")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--pkgrel-only", action="store_true")
    parser.add_argument(
        "--all-slkbuilds",
        action="store_true",
        help="Scan every tracked SLKBUILD instead of only files changed on this branch.",
    )
    args = parser.parse_args()

    repoRoot = Path(__file__).resolve().parent.parent

    try:
        slkbuildPaths = list_slkbuilds(repoRoot, not args.all_slkbuilds, args.base_ref)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if not slkbuildPaths:
        if args.all_slkbuilds:
            print("No tracked SLKBUILD files found.")
        else:
            print("No changed SLKBUILD files found.")
        return 0

    updatedPaths: list[tuple[str, str, str]] = []
    skippedPaths: list[str] = []

    for relativePath in slkbuildPaths:
        currentPath = repoRoot / relativePath
        if not currentPath.is_file():
            skippedPaths.append(f"{relativePath}: missing in worktree")
            continue

        if not file_exists_in_ref(args.base_ref, relativePath, repoRoot):
            skippedPaths.append(f"{relativePath}: new on branch")
            continue

        currentContent = currentPath.read_text(encoding="utf-8")
        baseContent = run_git(["show", f"{args.base_ref}:{relativePath}"], repoRoot)

        try:
            currentPkgver, _ = parse_assignment(currentContent, "pkgver")
            currentPkgrel, _ = parse_assignment(currentContent, "pkgrel")
            basePkgver, _ = parse_assignment(baseContent, "pkgver")
            basePkgrel, _ = parse_assignment(baseContent, "pkgrel")
        except ValueError as exc:
            skippedPaths.append(f"{relativePath}: {exc}")
            continue

        if currentPkgrel != basePkgrel:
            skippedPaths.append(
                f"{relativePath}: pkgrel differs already ({currentPkgrel} vs {basePkgrel})"
            )
            continue

        if not args.pkgrel_only and currentPkgver != basePkgver:
            skippedPaths.append(
                f"{relativePath}: pkgver differs ({currentPkgver} vs {basePkgver})"
            )
            continue

        try:
            newPkgrel = bump_pkgrel(currentPkgrel)
        except ValueError as exc:
            skippedPaths.append(f"{relativePath}: {exc}")
            continue
        updatedPaths.append((relativePath, currentPkgrel, newPkgrel))

        if args.apply:
            currentPath.write_text(
                update_pkgrel(currentContent, newPkgrel),
                encoding="utf-8",
            )

    actionWord = "Updated" if args.apply else "Would update"
    for relativePath, oldPkgrel, newPkgrel in updatedPaths:
        print(f"{actionWord} {relativePath}: {oldPkgrel} -> {newPkgrel}")

    for skippedLine in skippedPaths:
        print(f"Skipped {skippedLine}", file=sys.stderr)

    print(
        f"{actionWord.lower()} {len(updatedPaths)} package(s); skipped {len(skippedPaths)}.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
