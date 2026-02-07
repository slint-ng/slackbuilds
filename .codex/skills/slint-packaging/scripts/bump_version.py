#!/usr/bin/env python3
import argparse
import hashlib
import re
import tempfile
import urllib.request
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8', errors='replace')


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8')


def parse_var(text: str, name: str) -> str | None:
    m = re.search(rf'^{name}=("?)([^\n"]+)\1', text, re.M)
    return m.group(2) if m else None


def parse_source_entries(text: str) -> list[str]:
    m = re.search(r'^source=\((.*?)\)\s*$', text, re.M | re.S)
    if not m:
        return []
    raw = m.group(1)
    tokens = re.findall(r'"([^"]+)"|\'([^\']+)\'|(\S+)', raw)
    entries = []
    for a, b, c in tokens:
        entries.append(a or b or c)
    return entries


def substitute_vars(s: str, pkgname: str, pkgver: str) -> str:
    return (s.replace('${pkgname}', pkgname)
             .replace('$pkgname', pkgname)
             .replace('${pkgver}', pkgver)
             .replace('$pkgver', pkgver))


def file_hash(path: Path, algo: str) -> str:
    h = hashlib.new(algo)
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def update_sums(text: str, sources: list[str], pkgname: str, pkgver: str) -> tuple[str, list[str], list[str]]:
    sums = {'md5sums': 'md5', 'sha256sums': 'sha256', 'b2sums': 'blake2b'}
    computed = {}
    for key, algo in sums.items():
        if re.search(rf'^{key}=\(', text, re.M):
            computed[key] = []

    if not computed:
        return text, [], []

    for src in sources:
        src_eval = substitute_vars(src, pkgname, pkgver)
        if not re.match(r'^(https?|ftp)://', src_eval):
            for key in computed:
                computed[key].append('SKIP')
            continue
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / Path(src_eval).name
            urllib.request.urlretrieve(src_eval, dest)
            for key, algo in sums.items():
                if key in computed:
                    computed[key].append(file_hash(dest, algo))

    for key, values in computed.items():
        new_block = f"{key}=(" + ' '.join([f"'{v}'" for v in values]) + ")"
        text = re.sub(rf'^{key}=\(.*?\)\s*$', new_block, text, flags=re.M | re.S)

    return text, list(computed.keys()), list(computed.values())


def main() -> int:
    parser = argparse.ArgumentParser(description='Bump pkgver and refresh checksums in SLKBUILD')
    parser.add_argument('slkbuild', help='Path to SLKBUILD')
    parser.add_argument('version', help='New version')
    args = parser.parse_args()

    path = Path(args.slkbuild)
    if path.is_dir():
        path = path / 'SLKBUILD'
    if not path.exists():
        print(f"SLKBUILD not found: {path}")
        return 2

    text = read_text(path)
    old_ver = parse_var(text, 'pkgver') or ''
    pkgname = parse_var(text, 'pkgname') or ''

    if not pkgname:
        print('pkgname not found')
        return 2

    text = re.sub(r'^pkgver=.*$', f"pkgver={args.version}", text, flags=re.M)

    if old_ver:
        text = text.replace(old_ver, args.version)

    sources = parse_source_entries(text)
    if sources:
        text, sum_keys, _ = update_sums(text, sources, pkgname, args.version)
        if sum_keys:
            print(f"Updated sums: {', '.join(sum_keys)}")
        else:
            print('No sums present; none updated')
    else:
        print('No source entries found; sums not updated')

    write_text(path, text)
    print(f"Updated {path}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
