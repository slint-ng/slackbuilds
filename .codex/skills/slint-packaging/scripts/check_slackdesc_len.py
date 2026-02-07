#!/usr/bin/env python3
import argparse
from pathlib import Path


def extract_slackdesc_lines(text: str):
    lines = text.splitlines()
    in_block = False
    for line in lines:
        if not in_block:
            if line.strip().startswith('slackdesc='):
                in_block = True
            continue
        if line.strip() == ')':
            in_block = False
            continue
        if line.lstrip().startswith('"'):
            first = line.find('"')
            last = line.rfind('"')
            if first != -1 and last > first:
                yield line[first + 1:last]


def iter_slkbuilds(paths):
    for path in paths:
        p = Path(path)
        if p.is_dir():
            for slk in p.rglob('SLKBUILD'):
                yield slk
        elif p.is_file() and p.name == 'SLKBUILD':
            yield p


def main():
    parser = argparse.ArgumentParser(description='Check slackdesc line lengths and count.')
    parser.add_argument('paths', nargs='*', default=['.'], help='Files or directories to scan')
    parser.add_argument('--limit', type=int, default=70, help='Max chars per slackdesc line')
    parser.add_argument('--max-lines', type=int, default=10, help='Max slackdesc lines')
    parser.add_argument('--include-urls', action='store_true', help='Do not ignore URL lines')
    args = parser.parse_args()

    violations = []

    for slk in iter_slkbuilds(args.paths):
        text = slk.read_text(encoding='utf-8', errors='replace')
        slackdesc_lines = list(extract_slackdesc_lines(text))
        if not slackdesc_lines:
            continue
        if len(slackdesc_lines) > args.max_lines:
            violations.append((slk, 'line-count', len(slackdesc_lines), f'max {args.max_lines}'))
        for idx, line in enumerate(slackdesc_lines, 1):
            if not args.include_urls and '://' in line:
                continue
            if len(line) > args.limit:
                violations.append((slk, f'line {idx}', len(line), line))

    if not violations:
        print('OK: no slackdesc violations found')
        return 0

    for path, where, length, detail in violations:
        print(f"{path}: {where}: {length} {detail}")
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
