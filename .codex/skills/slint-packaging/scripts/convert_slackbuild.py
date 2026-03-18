#!/usr/bin/env python3
import argparse
import re
import shlex
from pathlib import Path
from typing import Optional

TARBALL_SUFFIXES = (
    '.tar',
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.lz',
    '.tar.zst',
    '.tgz',
    '.tbz',
    '.tbz2',
    '.txz',
)

BLOCKING_PATTERNS = (
    ("prepare()", re.compile(r'^\s*prepare\s*\(\)', re.M)),
    ("package()", re.compile(r'^\s*package\s*\(\)', re.M)),
    ("pkgdesc=", re.compile(r'^\s*pkgdesc=', re.M)),
    ("subpackages=", re.compile(r'^\s*subpackages=', re.M)),
    ("depends=", re.compile(r'^\s*depends\s*=', re.M)),
    ("makedepends=", re.compile(r'^\s*makedepends\s*=', re.M)),
    ("checkdepends=", re.compile(r'^\s*checkdepends\s*=', re.M)),
    ("optdepends=", re.compile(r'^\s*optdepends\s*=', re.M)),
    ("validpgpkeys=", re.compile(r'^\s*validpgpkeys=', re.M)),
    ("md5sums=", re.compile(r'^\s*md5sums=', re.M)),
    ("sha256sums=", re.compile(r'^\s*sha256sums=', re.M)),
    ("sha512sums=", re.compile(r'^\s*sha512sums=', re.M)),
    ("git+https source syntax", re.compile(r'git\+https://')),
    (
        "foreign maintainer/contributor header",
        re.compile(r'^\s*#\s*(?:Maintainer|Contributor)\b.*<[^>]+>', re.M | re.I),
    ),
    ("srcdir", re.compile(r'\bsrcdir\b')),
    ("pkgdir", re.compile(r'\bpkgdir\b')),
    ("builddir", re.compile(r'\bbuilddir\b')),
    ("startdir", re.compile(r'\bstartdir\b')),
    ("legacy `$PKGNAM` variable", re.compile(r'\$(?:\{)?PKGNAM(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$PRGNAM` variable", re.compile(r'\$(?:\{)?PRGNAM(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$VERSION` variable", re.compile(r'\$(?:\{)?VERSION(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$BUILD` variable", re.compile(r'\$(?:\{)?BUILD(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$TAG` variable", re.compile(r'\$(?:\{)?TAG(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$CWD` variable", re.compile(r'\$(?:\{)?CWD(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$TMP` variable", re.compile(r'\$(?:\{)?TMP(?:\})?(?![A-Za-z0-9_])')),
    ("legacy `$OUTPUT` variable", re.compile(r'\$(?:\{)?OUTPUT(?:\})?(?![A-Za-z0-9_])')),
)

LEGACY_REF_PATTERNS = (
    re.compile(r'\bslack-desc\b'),
    re.compile(r'\bdoinst\.sh\b'),
    re.compile(r'\.info\b'),
    re.compile(r'\.SlackBuild\b'),
)

IGNORED_LOCAL_SOURCE_SUFFIXES = (
    '.dep',
    '.log',
    '.md5',
    '.news',
    '.sha1',
    '.sha256',
    '.sha256sum',
    '.sha512',
    '.sha512sum',
    '.url',
)

IGNORED_LOCAL_SOURCE_NAMES = {
    '.gitignore',
    'README',
    'README.SBo',
    'SLKBUILD',
    'doinst.sh',
    'slack-desc',
}

PKG_PATH_PATTERNS = (
    re.compile(r'"\$PKG"/([^"\s;|)]+)'),
    re.compile(r'"\$\{PKG\}"/([^"\s;|)]+)'),
    re.compile(r'\$PKG/([^\s"\';|)]+)'),
    re.compile(r'\$\{PKG\}/([^\s"\';|)]+)'),
    re.compile(r'"\$startdir/pkg/([^"\s;|)]+)'),
    re.compile(r'"\$\{startdir\}/pkg/([^"\s;|)]+)'),
    re.compile(r'\$startdir/pkg/([^\s"\';|)]+)'),
    re.compile(r'\$\{startdir\}/pkg/([^\s"\';|)]+)'),
)

REDUNDANT_FLAG_ASSIGNMENT = r'(?:CFLAGS|CXXFLAGS)=(?:"\$(?:\{)?SLKCFLAGS(?:\})?"|\'\$(?:\{)?SLKCFLAGS(?:\})?\'|\$(?:\{)?SLKCFLAGS(?:\})?)'


def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8', errors='replace')


def parse_info(info_path: Path) -> dict:
    data = {}
    logical_lines = []
    continued = ''
    for raw_line in read_text(info_path).splitlines():
        line = raw_line.rstrip()
        if continued:
            line = continued + line.lstrip()
        if line.endswith('\\'):
            continued = line[:-1].rstrip() + ' '
            continue
        logical_lines.append(line)
        continued = ''

    if continued:
        logical_lines.append(continued.rstrip())

    for line in logical_lines:
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


def is_remote_source(value: str) -> bool:
    return value.startswith('git+') or bool(re.match(r'^[A-Za-z][A-Za-z0-9+.-]*://', value))


def strip_source_fragment_and_query(value: str) -> str:
    return value.split('#', 1)[0].split('?', 1)[0]


def is_https_source(value: str) -> bool:
    return strip_source_fragment_and_query(value).lower().startswith('https://')


def is_vcs_source(value: str) -> bool:
    normalized = value.strip().lower()
    base = strip_source_fragment_and_query(normalized)
    if base.startswith(('git://', 'svn://', 'hg://', 'bzr://', 'git+')):
        return True
    if base.endswith('.git'):
        return True
    if '.git/' in base:
        return True
    if '#tag=' in normalized or '#branch=' in normalized or '#commit=' in normalized:
        return True
    return False


def is_tarball_source(value: str) -> bool:
    base = strip_source_fragment_and_query(value).lower()
    return base.endswith(TARBALL_SUFFIXES)


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen = set()
    result = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def looks_like_local_source(name: str) -> bool:
    if name in IGNORED_LOCAL_SOURCE_NAMES:
        return False
    if name.endswith('.SlackBuild') or name.endswith('.info'):
        return False
    if any(name.endswith(suffix) for suffix in IGNORED_LOCAL_SOURCE_SUFFIXES):
        return False
    if name.endswith(('~', '.bak', '.orig', '.rej')):
        return False
    return True


def collect_local_sources(pkg_dir: Path, slackbuild_text: str) -> list[str]:
    local_sources = []
    for path in sorted(pkg_dir.iterdir()):
        if not path.is_file():
            continue
        name = path.name
        if not looks_like_local_source(name):
            continue
        if name in slackbuild_text:
            local_sources.append(name)
    return local_sources


def extract_array_entries(text: str, varname: str) -> list[str]:
    source_lines = []
    depth = 0
    collecting = False

    for line in text.splitlines():
        if not collecting:
            match = re.match(rf'^\s*{re.escape(varname)}=\((.*)$', line)
            if not match:
                continue
            collecting = True
            remainder = match.group(1)
            source_lines.append(remainder)
            depth = 1 + remainder.count('(') - remainder.count(')')
        else:
            source_lines.append(line)
            depth += line.count('(') - line.count(')')

        if collecting and depth <= 0:
            break

    if not source_lines:
        return []

    source_text = '\n'.join(source_lines)
    entries = []
    for match in re.finditer(r'"([^"]+)"|\'([^\']+)\'|([^\s()]+)', source_text):
        entry = next((group for group in match.groups() if group), '')
        if entry:
            entries.append(entry)
    return dedupe_preserve_order(entries)


def render_array_block(varname: str, entries: list[str]) -> list[str]:
    if not entries:
        return []
    if len(entries) == 1:
        return [f'{varname}=("{entries[0]}")']
    lines = [f"{varname}=("]
    for entry in entries:
        lines.append(f'  "{entry}"')
    lines.append(")")
    return lines


def render_source_block(entries: list[str]) -> list[str]:
    if not entries:
        return ["source=()"]
    if len(entries) == 1:
        return [f'source=("{entries[0]}")']
    lines = ["source=("]
    for entry in entries:
        lines.append(f'  "{entry}"')
    lines.append(")")
    return lines


def has_inline_slackdesc(text: str) -> bool:
    return bool(re.search(r'^\s*slackdesc=', text, re.M))


def remove_function_block(lines: list[str], func_name: str) -> list[str]:
    result = []
    skip = False
    depth = 0

    for line in lines:
        if not skip:
            if re.match(rf'^\s*(?:function\s+)?{re.escape(func_name)}\s*\(\)\s*\{{\s*$', line):
                skip = True
                depth = line.count('{') - line.count('}')
                if depth <= 0:
                    skip = False
                continue
            result.append(line)
            continue

        depth += line.count('{') - line.count('}')
        if depth <= 0:
            skip = False

    return result


def extract_dotnew_entries_from_doinst(doinst_body: str) -> tuple[list[str], Optional[str]]:
    remaining_lines = []
    dotnew_entries = []

    for line in doinst_body.splitlines():
        stripped = line.strip()
        match = re.match(r'^(config|dotnew)\s+(etc/\S+?)(?:\.new)?(?:\s+#.*)?$', stripped)
        if match:
            dotnew_entries.append(match.group(2))
            continue
        remaining_lines.append(line)

    if dotnew_entries:
        if not any(re.match(r'^\s*config\s+', line) for line in remaining_lines):
            remaining_lines = remove_function_block(remaining_lines, 'config')
        if not any(re.match(r'^\s*dotnew\s+', line) for line in remaining_lines):
            remaining_lines = remove_function_block(remaining_lines, 'dotnew')

    while remaining_lines and not remaining_lines[0].strip():
        remaining_lines.pop(0)
    while remaining_lines and not remaining_lines[-1].strip():
        remaining_lines.pop()

    return dedupe_preserve_order(dotnew_entries), '\n'.join(remaining_lines).rstrip() or None


def extract_pkg_paths_from_line(line: str) -> list[str]:
    paths = []
    for pattern in PKG_PATH_PATTERNS:
        for match in pattern.finditer(line):
            path = match.group(1).lstrip('/')
            if path:
                paths.append(path)
    return dedupe_preserve_order(paths)


def iter_command_spans(lines: list[str]) -> list[tuple[int, int, list[str]]]:
    spans = []
    start = 0
    idx = 0

    while idx < len(lines):
        span_lines = [lines[idx]]
        end = idx
        while span_lines[-1].rstrip().endswith('\\') and end + 1 < len(lines):
            end += 1
            span_lines.append(lines[end])
        spans.append((start, end, span_lines))
        idx = end + 1
        start = idx

    return spans


def normalize_command_text(span_lines: list[str]) -> str:
    parts = []
    for line in span_lines:
        stripped = line.strip()
        if stripped.endswith('\\'):
            stripped = stripped[:-1].rstrip()
        parts.append(stripped)
    return ' '.join(parts).strip()


def looks_like_doc_dest(token: str) -> bool:
    return any(
        marker in token
        for marker in (
            '$PKG/usr/doc/',
            '$PKG/usr/share/doc/',
            '${PKG}/usr/doc/',
            '${PKG}/usr/share/doc/',
            '$startdir/pkg/usr/doc/',
            '$startdir/pkg/usr/share/doc/',
            '${startdir}/pkg/usr/doc/',
            '${startdir}/pkg/usr/share/doc/',
        )
    )


def normalize_doc_token(token: str) -> str:
    while token.startswith('./'):
        token = token[2:]
    return token


def looks_like_docs_entry(token: str) -> bool:
    token = normalize_doc_token(token)
    if not token or token.startswith('-'):
        return False
    if any(marker in token for marker in ('$', '{', '}', '(', ')', ';', '|')):
        return False
    if token in ('{}',):
        return False
    if '/' in token:
        return False
    return True


def parse_cp_docs_command(command_text: str) -> list[str]:
    try:
        tokens = shlex.split(re.sub(r'\s+\|\|.*$', '', command_text))
    except ValueError:
        return []

    if not tokens or tokens[0] != 'cp' or len(tokens) < 3:
        return []

    dest = tokens[-1]
    if not looks_like_doc_dest(dest):
        return []

    docs = []
    for token in tokens[1:-1]:
        if token == '--':
            continue
        if token.startswith('-'):
            continue
        if token in ('&&', '||'):
            return []
        if not looks_like_docs_entry(token):
            return []
        docs.append(normalize_doc_token(token))

    return dedupe_preserve_order(docs)


def parse_install_docs_command(command_text: str) -> list[str]:
    try:
        tokens = shlex.split(re.sub(r'\s+\|\|.*$', '', command_text))
    except ValueError:
        return []

    if not tokens or tokens[0] != 'install' or len(tokens) < 3:
        return []

    dest = tokens[-1]
    if not looks_like_doc_dest(dest):
        return []

    docs = []
    idx = 1
    while idx < len(tokens) - 1:
        token = tokens[idx]
        if token == '--':
            idx += 1
            continue
        if token.startswith('-'):
            idx += 1
            # `install -m 644 ...` and similar take a following argument.
            if token in ('-m', '-o', '-g', '-t') and idx < len(tokens) - 1:
                idx += 1
            continue
        if not looks_like_docs_entry(token):
            return []
        docs.append(normalize_doc_token(token))
        idx += 1

    return dedupe_preserve_order(docs)


def parse_find_docs_command(command_text: str) -> list[str]:
    stripped = re.sub(r'\s+\|\|.*$', '', command_text)
    if not stripped.startswith('find ') or ' -exec ' not in stripped:
        return []
    if '/usr/doc/' not in stripped and '/usr/share/doc/' not in stripped:
        return []

    try:
        tokens = shlex.split(stripped)
    except ValueError:
        return []

    if '-exec' not in tokens:
        return []
    exec_index = tokens.index('-exec')
    if exec_index + 1 >= len(tokens) or tokens[exec_index + 1] not in ('cp', 'install'):
        return []

    docs = []
    for idx, token in enumerate(tokens[:-1]):
        if token not in ('-name', '-iname'):
            continue
        candidate = tokens[idx + 1]
        if not looks_like_docs_entry(candidate):
            return []
        docs.append(normalize_doc_token(candidate))

    return dedupe_preserve_order(docs)


def looks_like_doc_mkdir_command(command_text: str) -> bool:
    return bool(
        re.search(
            r'^\s*mkdir\s+-p\s+.*(?:\$PKG|\$\{PKG\}|\$startdir/pkg|\$\{startdir\}/pkg)/usr/(?:share/)?doc/',
            command_text,
        )
    )


def line_references_doc_dest(line: str) -> bool:
    return '/usr/doc/' in line or '/usr/share/doc/' in line


def extract_docs_entries_from_build(lines: list[str]) -> tuple[list[str], list[str]]:
    docs_entries = []
    spans_to_remove = set()
    mkdir_candidates = []

    for start, end, span_lines in iter_command_spans(lines):
        command_text = normalize_command_text(span_lines)
        docs = parse_cp_docs_command(command_text)
        if not docs:
            docs = parse_install_docs_command(command_text)
        if not docs:
            docs = parse_find_docs_command(command_text)

        if docs:
            docs_entries.extend(docs)
            spans_to_remove.update(range(start, end + 1))
            continue

        if looks_like_doc_mkdir_command(command_text):
            mkdir_candidates.append((start, end))

    if spans_to_remove:
        mkdir_candidate_lines = set()
        for start, end in mkdir_candidates:
            mkdir_candidate_lines.update(range(start, end + 1))
        if not any(
            line_references_doc_dest(line)
            for idx, line in enumerate(lines)
            if idx not in spans_to_remove
            and idx not in mkdir_candidate_lines
        ):
            for start, end in mkdir_candidates:
                spans_to_remove.update(range(start, end + 1))

    kept_lines = [line for idx, line in enumerate(lines) if idx not in spans_to_remove]

    return dedupe_preserve_order(docs_entries), kept_lines


def command_references_pkg_tree(command_text: str) -> bool:
    return any(
        token in command_text
        for token in (
            '$PKG',
            '${PKG}',
            '$startdir/pkg',
            '${startdir}/pkg',
        )
    )


def looks_like_pkg_root_find(command_text: str, in_pkg_context: bool = False) -> bool:
    normalized = re.sub(r'\s+', ' ', command_text).strip()
    if in_pkg_context:
        return normalized.startswith(('find .', 'find -L .', 'find ./', 'find -L ./'))
    return normalized.startswith(
        (
            'find $PKG',
            'find "$PKG"',
            'find ${PKG}',
            'find "${PKG}"',
            'find $startdir/pkg',
            'find "$startdir/pkg"',
            'find ${startdir}/pkg',
            'find "${startdir}/pkg"',
        )
    )


def looks_like_generic_strip_command(command_text: str, in_pkg_context: bool = False) -> bool:
    normalized = re.sub(r'\s+', ' ', re.sub(r'\s+\|\|.*$', '', command_text)).strip()
    if 'strip --strip-unneeded' not in normalized:
        return False
    if 'file' not in normalized or 'ELF' not in normalized or 'xargs' not in normalized:
        return False
    if 'executable' not in normalized and 'shared object' not in normalized:
        return False
    if not looks_like_pkg_root_find(normalized, in_pkg_context=in_pkg_context):
        return False
    if not in_pkg_context and not command_references_pkg_tree(normalized):
        return False
    return True


def looks_like_strip_comment(line: str) -> bool:
    return bool(re.match(r'^\s*#\s*Strip binaries:?\s*$', line))


def looks_like_pkg_cd_subshell_start(line: str) -> bool:
    stripped = line.strip()
    if not stripped.startswith('(') or ')' in stripped:
        return False
    if 'cd' not in stripped:
        return False
    return command_references_pkg_tree(stripped)


def extract_standard_strip_logic(lines: list[str]) -> list[str]:
    lines_to_remove = set()
    idx = 0

    while idx < len(lines):
        if not looks_like_pkg_cd_subshell_start(lines[idx]):
            idx += 1
            continue

        end = idx + 1
        while end < len(lines) and lines[end].strip() != ')':
            end += 1
        if end >= len(lines):
            idx += 1
            continue

        commands = []
        for line in lines[idx + 1:end]:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            commands.append(normalize_command_text([line]))

        if commands and all(looks_like_generic_strip_command(command, in_pkg_context=True) for command in commands):
            lines_to_remove.update(range(idx, end + 1))
            idx = end + 1
            continue

        idx += 1

    for start, end, span_lines in iter_command_spans(lines):
        if any(idx in lines_to_remove for idx in range(start, end + 1)):
            continue
        command_text = normalize_command_text(span_lines)
        if looks_like_generic_strip_command(command_text):
            lines_to_remove.update(range(start, end + 1))

    for idx, line in enumerate(lines):
        if idx in lines_to_remove or not looks_like_strip_comment(line):
            continue
        next_nonblank = next((pos for pos in range(idx + 1, len(lines)) if lines[pos].strip()), None)
        if next_nonblank is not None and next_nonblank in lines_to_remove:
            lines_to_remove.add(idx)

    return [line for idx, line in enumerate(lines) if idx not in lines_to_remove]


def is_redundant_flag_export(line: str) -> bool:
    return bool(
        re.match(
            rf'^\s*export\s+{REDUNDANT_FLAG_ASSIGNMENT}\s*$',
            line,
        )
    )


def is_redundant_flag_prefix_only(line: str) -> bool:
    return bool(
        re.match(
            rf'^\s*{REDUNDANT_FLAG_ASSIGNMENT}\s*\\\s*$',
            line,
        )
    )


def strip_redundant_flag_prefixes_in_line(line: str) -> str:
    patterns = (
        rf'(^\s*)((?:{REDUNDANT_FLAG_ASSIGNMENT}\s+)+)(?=\S)',
        rf'(\|\s*)((?:{REDUNDANT_FLAG_ASSIGNMENT}\s+)+)(?=\S)',
        rf'(&&\s*)((?:{REDUNDANT_FLAG_ASSIGNMENT}\s+)+)(?=\S)',
        rf'(\|\|\s*)((?:{REDUNDANT_FLAG_ASSIGNMENT}\s+)+)(?=\S)',
    )
    for pattern in patterns:
        while True:
            updated = re.sub(pattern, r'\1', line)
            if updated == line:
                break
            line = updated
    return line


def extract_redundant_compiler_flag_setup(lines: list[str]) -> list[str]:
    cleaned_lines = []
    for line in lines:
        if is_redundant_flag_export(line):
            continue
        if is_redundant_flag_prefix_only(line):
            continue
        cleaned_lines.append(strip_redundant_flag_prefixes_in_line(line))
    return cleaned_lines


def collect_dotnew_candidates_from_lines(lines: list[str]) -> list[str]:
    candidates = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if re.match(r'^(mkdir|rmdir)\b', stripped):
            continue
        if re.match(r'^install\b', stripped) and re.search(r'(^|\s)-d(\s|$)', stripped) and '-D' not in stripped:
            continue

        paths = extract_pkg_paths_from_line(line)
        for path in paths:
            if not path.startswith('etc/'):
                continue
            if '.new.incoming' in path:
                continue

            normalized = path[:-4] if path.endswith('.new') else path
            if normalized.endswith('/') or any(token in normalized for token in ('*', '{', '}', '$(')):
                continue

            if path.endswith('.new'):
                candidates.append(normalized)
                continue
            if re.search(r'\binstall\b.*-[^\n#]*D', stripped):
                candidates.append(normalized)
                continue
            if '>' in stripped:
                candidates.append(normalized)

    return dedupe_preserve_order(candidates)


def normalize_known_path_vars(path: str, pkgname: str, pkgver: str) -> str:
    replacements = {
        '$PKGNAM': pkgname,
        '${PKGNAM}': pkgname,
        '$PRGNAM': pkgname,
        '${PRGNAM}': pkgname,
        '$pkgname': pkgname,
        '${pkgname}': pkgname,
        '$VERSION': pkgver,
        '${VERSION}': pkgver,
        '$pkgver': pkgver,
        '${pkgver}': pkgver,
    }
    for old, new in replacements.items():
        if new:
            path = path.replace(old, new)
    return path


def audit_generated_slkbuild(pkg_dir: Path, rendered_text: str, source_entries: list[str]) -> list[str]:
    issues = []
    pkgname_match = re.search(r'^\s*pkgname=([^\s#]+)', rendered_text, re.M)
    pkgver_match = re.search(r'^\s*pkgver=([^\s#]+)', rendered_text, re.M)
    rendered_pkgname = pkgname_match.group(1) if pkgname_match else ''
    rendered_pkgver = pkgver_match.group(1) if pkgver_match else ''

    for label, pattern in BLOCKING_PATTERNS:
        if pattern.search(rendered_text):
            issues.append(f"contains foreign packaging marker `{label}`")
    for pattern in LEGACY_REF_PATTERNS:
        if pattern.search(rendered_text):
            issues.append("still references legacy SlackBuild metadata files")
            break
    for entry in source_entries:
        if is_remote_source(entry):
            if is_vcs_source(entry):
                issues.append(
                    "uses VCS source `"
                    + entry
                    + "`; require release tarballs unless an approved exception is documented"
                )
                continue
            if not is_https_source(entry):
                issues.append(
                    "uses non-HTTPS remote source `"
                    + entry
                    + "`; require HTTPS tarball provenance"
                )
            if not is_tarball_source(entry):
                issues.append(
                    "uses non-tarball remote source `"
                    + entry
                    + "`; require versioned release tarballs"
                )
            continue
        if not (pkg_dir / entry).exists():
            if allow_missing_generated_local_source(pkg_dir, entry):
                continue
            issues.append(f"declares missing local source `{entry}`")
    dotnew_entries = extract_array_entries(rendered_text, 'dotnew')
    if dotnew_entries:
        dotnew_entries = [
            normalize_known_path_vars(entry, rendered_pkgname, rendered_pkgver)
            for entry in dotnew_entries
        ]
        candidates = [
            normalize_known_path_vars(path, rendered_pkgname, rendered_pkgver)
            for path in collect_dotnew_candidates_from_lines(rendered_text.splitlines())
        ]
        missing = [path for path in candidates if path not in dotnew_entries]
        for path in missing:
            issues.append(
                "dotnew omits `/"
                + path
                + "`; explicit `dotnew=()` disables slkbuild's `/etc` auto-discovery fallback"
            )
    if re.search(r'\b(git clone|curl\s|wget\s|svn\s|hg\s)\b', rendered_text):
        issues.append("fetches sources during build; move them into `source=()`")
    if not has_inline_slackdesc(rendered_text):
        issues.append("is missing an inline `slackdesc` block")
    return dedupe_preserve_order(issues)


def allow_missing_generated_local_source(pkg_dir: Path, entry: str) -> bool:
    fetch_script = pkg_dir / 'fetch_sources.sh'
    readme = pkg_dir / 'README'

    if not fetch_script.exists() or not readme.exists():
        return False

    try:
        readme_text = readme.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return False

    return 'fetch_sources.sh' in readme_text and entry in readme_text


def find_legacy_files(pkg_dir: Path) -> list[str]:
    legacy_files = []
    legacy_files.extend(sorted(pkg_dir.glob('*.SlackBuild')))
    legacy_files.extend(sorted(pkg_dir.glob('*.info')))
    for name in ('slack-desc', 'doinst.sh'):
        path = pkg_dir / name
        if path.exists():
            legacy_files.append(path)
    return dedupe_preserve_order([str(path) for path in legacy_files])


def extract_source_entries(text: str) -> list[str]:
    return extract_array_entries(text, 'source')


def looks_like_pkg_style_dep_filename(dep_name: str) -> bool:
    if not dep_name.endswith('.dep'):
        return False
    stem = dep_name[:-4]
    # Expected form: <pkgname>-<pkgver>-<arch>-<pkgrel>.dep
    return stem.count('-') >= 3


def audit_existing_package_dir(pkg_dir: Path) -> list[str]:
    slkbuild_path = pkg_dir / 'SLKBUILD'
    if not slkbuild_path.exists():
        return ["missing `SLKBUILD`"]

    rendered_text = read_text(slkbuild_path)
    issues = audit_generated_slkbuild(pkg_dir, rendered_text, extract_source_entries(rendered_text))

    legacy_files = find_legacy_files(pkg_dir)
    if legacy_files:
        issues.append(
            "legacy conversion files still present: " + ', '.join(Path(path).name for path in legacy_files)
        )

    pkgname_match = re.search(r'^\s*pkgname=([^\s#]+)', rendered_text, re.M)
    if pkgname_match:
        placeholder_dep = pkg_dir / f"{pkgname_match.group(1)}.dep"
        if placeholder_dep.exists():
            issues.append(f"placeholder dependency metadata still present: `{placeholder_dep.name}`")

    placeholder_dep_name = f"{pkgname_match.group(1)}.dep" if pkgname_match else None
    for dep_path in sorted(pkg_dir.glob('*.dep')):
        if dep_path.name == placeholder_dep_name:
            continue
        if not looks_like_pkg_style_dep_filename(dep_path.name):
            issues.append(f"dependency metadata filename is not package-style: `{dep_path.name}`")

    first_nonblank = next((line for line in rendered_text.splitlines() if line.strip()), '')
    if not (
        first_nonblank.startswith('#!/bin/bash')
        or first_nonblank.startswith('# shellcheck shell=bash')
    ):
        issues.append("missing bash shebang or shellcheck bash directive at top of `SLKBUILD`")

    return dedupe_preserve_order(issues)


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
    parser.add_argument(
        '--apply',
        action='store_true',
        help='Write SLKBUILD and remove old files only if conversion gates pass',
    )
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
    slackbuild_text = read_text(slackbuild)

    pkgname = slackbuild.stem
    pkgver = ''
    pkgrel = '1slint'
    source_list = []
    url = ''
    info = {}

    info_path = pkg_dir / f"{pkgname}.info"
    if info_path.exists():
        info = parse_info(info_path)
        pkgver = info.get('VERSION', pkgver)
        url = info.get('HOMEPAGE', url)
        download = info.get('DOWNLOAD', '')
        if download:
            source_list = [entry for entry in download.split() if entry]

    # fallback: parse VERSION/BUILD/TAG from SlackBuild
    if not pkgver:
        m = re.search(r'^VERSION=\"?([^\"\n]+)\"?', slackbuild_text, re.M)
        if m:
            pkgver = m.group(1)
    m_build = re.search(r'^BUILD=\"?([^\"\n]+)\"?', slackbuild_text, re.M)
    m_tag = re.search(r'^TAG=\"?([^\"\n]+)\"?', slackbuild_text, re.M)
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
    dotnew_entries = []
    if doinst_path.exists():
        dotnew_entries, doinst_body = extract_dotnew_entries_from_doinst(
            strip_shebang(read_text(doinst_path)).rstrip()
        )

    body_lines = extract_build_body(slackbuild)
    body_lines = extract_redundant_compiler_flag_setup(body_lines)
    body_lines = extract_standard_strip_logic(body_lines)
    docs_entries, body_lines = extract_docs_entries_from_build(body_lines)
    dotnew_entries.extend(collect_dotnew_candidates_from_lines(body_lines))
    dotnew_entries = [
        normalize_known_path_vars(entry, pkgname, pkgver)
        for entry in dotnew_entries
    ]
    dotnew_entries = dedupe_preserve_order(dotnew_entries)
    docs_entries = dedupe_preserve_order(docs_entries)
    source_list.extend(collect_local_sources(pkg_dir, slackbuild_text))
    source_list = dedupe_preserve_order(source_list)

    options = []
    if 'git clone' in slackbuild_text and not source_list:
        options.append("'nosrcpack'")

    out_lines = []
    out_lines.append("# shellcheck shell=bash disable=SC2034")
    out_lines.append(f"# Packager: {Path.home().name}")
    out_lines.append('')
    out_lines.append(f"pkgname={pkgname}")
    if pkgver:
        out_lines.append(f"pkgver={pkgver}")
    else:
        out_lines.append("pkgver=")
    out_lines.append(f"pkgrel={pkgrel}")
    out_lines.extend(render_source_block(source_list))
    if url:
        out_lines.append(f"url=\"{url}\"")
    if docs_entries:
        out_lines.extend(render_array_block('docs', docs_entries))
    if options:
        out_lines.append(f"options=({ ' '.join(options) })")
    if dotnew_entries:
        out_lines.extend(render_array_block('dotnew', dotnew_entries))
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
    issues = audit_generated_slkbuild(pkg_dir, out_text, source_list)

    slkbuild_path = pkg_dir / 'SLKBUILD'
    if args.apply:
        slkbuild_path.write_text(out_text, encoding='utf-8')
        if not args.keep_files and not issues:
            for path in find_legacy_files(pkg_dir):
                Path(path).unlink()
        print(f"Wrote {slkbuild_path}")
        if issues and not args.keep_files:
            print("Kept legacy conversion files for manual review because conversion gates failed.")
    else:
        print(out_text)
        print(f"# Preview only. Use --apply to write {slkbuild_path}")
    if issues:
        print("# Conversion gates failed:")
        for issue in issues:
            print(f"# - {issue}")
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
