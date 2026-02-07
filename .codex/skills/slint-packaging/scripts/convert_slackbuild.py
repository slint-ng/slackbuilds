#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8', errors='replace')


def parse_info(info_path: Path) -> dict:
    data = {}
    for line in read_text(info_path).splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip().strip('"')
        data[key] = value
    return data


def parse_slackdesc(slack_desc_path: Path, max_lines: int) -> list[str]:
    lines = []
    for line in read_text(slack_desc_path).splitlines():
        if line.startswith('#') or 'handy-ruler' in line:
            continue
        if ':' in line:
            lines.append(line.rstrip())
    if len(lines) <= max_lines:
        return lines
    # trim trailing blanks first
    while len(lines) > max_lines and lines and lines[-1].endswith(':'):
        lines.pop()
    return lines[:max_lines]


def strip_shebang(text: str) -> str:
    lines = text.splitlines()
    if lines and lines[0].startswith('#!'):
        return '\n'.join(lines[1:])
    return text


def extract_build_body(slackbuild_path: Path) -> list[str]:
    lines = read_text(slackbuild_path).splitlines()
    # Find end before makepkg
    end = None
    for i, line in enumerate(lines):
        if 'makepkg' in line:
            end = i
            break
    if end is None:
        end = len(lines)

    # Start after set -e if present, else first rm -rf/mkdir/cd to TMP/CWD
    start = None
    for i, line in enumerate(lines):
        if re.match(r'^\s*set\s+-e', line):
            start = i + 1
            break
    if start is None:
        for i, line in enumerate(lines):
            if re.match(r'^\s*(rm -rf|mkdir -p|cd \$TMP|cd \$CWD|cd \$PWD)', line):
                start = i
                break
    if start is None:
        start = 0

    body = lines[start:end]
    filtered = []
    drop_patterns = [
        'slack-desc',
        'doinst.sh',
        'makepkg',
        'md5sum',
        'pkgname.SlackBuild',
        'SlackBuild >',
    ]
    for line in body:
        if any(pat in line for pat in drop_patterns):
            continue
        filtered.append(line)
    # Remove trailing blank lines
    while filtered and not filtered[-1].strip():
        filtered.pop()
    return filtered


def main() -> int:
    parser = argparse.ArgumentParser(description='Scaffold SLKBUILD from SlackBuild')
    parser.add_argument('package_dir', help='Package directory')
    parser.add_argument('--max-lines', type=int, default=10, help='Max slackdesc lines')
    parser.add_argument('--apply', action='store_true', help='Write SLKBUILD and remove old files')
    parser.add_argument('--keep-files', action='store_true', help='Do not delete old files')
    args = parser.parse_args()

    pkg_dir = Path(args.package_dir).resolve()
    if not pkg_dir.is_dir():
        print(f"Not a directory: {pkg_dir}")
        return 2

    slackbuilds = list(pkg_dir.glob('*.SlackBuild'))
    if len(slackbuilds) != 1:
        print(f"Expected exactly one *.SlackBuild, found {len(slackbuilds)}")
        return 2
    slackbuild = slackbuilds[0]

    pkgname = slackbuild.stem
    pkgver = ''
    pkgrel = '1slint'
    source_list = []
    url = ''

    info_path = pkg_dir / f"{pkgname}.info"
    if info_path.exists():
        info = parse_info(info_path)
        pkgver = info.get('VERSION', pkgver)
        url = info.get('HOMEPAGE', url)
        download = info.get('DOWNLOAD', '')
        if download and download != '':
            source_list = [download]

    # fallback: parse VERSION/BUILD/TAG from SlackBuild
    if not pkgver:
        text = read_text(slackbuild)
        m = re.search(r'^VERSION=\"?([^\"\n]+)\"?', text, re.M)
        if m:
            pkgver = m.group(1)
    m_build = re.search(r'^BUILD=\"?([^\"\n]+)\"?', read_text(slackbuild), re.M)
    m_tag = re.search(r'^TAG=\"?([^\"\n]+)\"?', read_text(slackbuild), re.M)
    if m_build:
        build = m_build.group(1)
        tag = m_tag.group(1) if m_tag else ''
        if tag and not build.endswith(tag):
            pkgrel = f"{build}{tag}"
        else:
            pkgrel = build

    slackdesc_lines = []
    slack_desc_path = pkg_dir / 'slack-desc'
    if slack_desc_path.exists():
        slackdesc_lines = parse_slackdesc(slack_desc_path, args.max_lines)

    doinst_path = pkg_dir / 'doinst.sh'
    doinst_body = None
    if doinst_path.exists():
        doinst_body = strip_shebang(read_text(doinst_path)).rstrip()

    body_lines = extract_build_body(slackbuild)

    options = []
    if 'git clone' in read_text(slackbuild) and not source_list:
        options.append("'nosrcpack'")

    out_lines = []
    out_lines.append(f"# Packager: {Path.home().name}")
    out_lines.append('')
    out_lines.append(f"pkgname={pkgname}")
    if pkgver:
        out_lines.append(f"pkgver={pkgver}")
    else:
        out_lines.append("pkgver=")
    out_lines.append(f"pkgrel={pkgrel}")
    if source_list:
        sources = ' '.join([f"\"{s}\"" for s in source_list])
        out_lines.append(f"source=({sources})")
    else:
        out_lines.append("source=()")
    if url:
        out_lines.append(f"url=\"{url}\"")
    if options:
        out_lines.append(f"options=({ ' '.join(options) })")
    out_lines.append("")

    if slackdesc_lines:
        out_lines.append("slackdesc=\\")
        out_lines.append("(")
        out_lines.append("#|-----handy-ruler------------------------------------------------------|")
        for line in slackdesc_lines:
            out_lines.append(f"\"{line}\"")
        out_lines.append(")")
        out_lines.append("")

    if doinst_body:
        out_lines.append("doinst() {")
        for line in doinst_body.splitlines():
            out_lines.append(line)
        out_lines.append("}")
        out_lines.append("")

    out_lines.append("build() {")
    if not body_lines:
        out_lines.append("  # TODO: port build steps from the original SlackBuild")
    else:
        for line in body_lines:
            out_lines.append(f"  {line}")
    out_lines.append("}")
    out_text = '\n'.join(out_lines) + '\n'

    slkbuild_path = pkg_dir / 'SLKBUILD'
    if args.apply:
        slkbuild_path.write_text(out_text, encoding='utf-8')
        if not args.keep_files:
            slackbuild.unlink()
            if slack_desc_path.exists():
                slack_desc_path.unlink()
            if doinst_path.exists():
                doinst_path.unlink()
            if info_path.exists():
                info_path.unlink()
        print(f"Wrote {slkbuild_path}")
    else:
        print(out_text)
        print(f"# Preview only. Use --apply to write {slkbuild_path}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
