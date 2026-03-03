#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ast
import importlib
import importlib.util
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_SOURCE_ROOT = Path("/home/storm/devel/cthulhu")
DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]

packageHints = {
    "PIL": ["python3-pillow"],
    "Xlib": ["python3-xlib", "python-xlib"],
    "brlapi": ["brltty"],
    "cairo": ["pycairo3.11", "pycairo"],
    "dasbus": ["python3-dasbus"],
    "gi": ["pygobject3.11", "pygobject3"],
    "gi.repository.Atk": ["atk"],
    "gi.repository.Atspi": ["python-atspi", "at-spi2-core"],
    "gi.repository.Gdk": ["gtk+3"],
    "gi.repository.GdkPixbuf": ["gdk-pixbuf2"],
    "gi.repository.Gio": ["glib2"],
    "gi.repository.GLib": ["glib2"],
    "gi.repository.GObject": ["glib2"],
    "gi.repository.Gst": ["gstreamer", "gst-plugins-base", "gst-plugins-good"],
    "gi.repository.Gtk": ["gtk+3"],
    "gi.repository.Pango": ["pango"],
    "gi.repository.Wnck": ["libwnck3"],
    "louis": ["liblouis"],
    "msgpack": ["python3-msgpack"],
    "pdf2image": ["python-pdf2image"],
    "piper": ["piper-tts"],
    "pluggy": ["python3-pluggy"],
    "psutil": ["psutil3.11", "psutil"],
    "pyautogui": ["python3-pyautogui"],
    "pytesseract": ["python-pytesseract"],
    "requests": ["python-requests"],
    "scipy": ["python-scipy"],
    "setproctitle": ["python3-setproctitle"],
    "speechd": ["speech-dispatcher3.11", "speech-dispatcher"],
    "tomlkit": ["python3-tomlkit", "python-tomlkit"],
    "tornado": ["python3-tornado"],
    "webcolors": ["python-webcolors"],
}

giVersions = {
    "Atk": "1.0",
    "Atspi": "2.0",
    "Gdk": "3.0",
    "GdkPixbuf": "2.0",
    "Gio": "2.0",
    "GLib": "2.0",
    "GObject": "2.0",
    "Gst": "1.0",
    "Gtk": "3.0",
    "Pango": "1.0",
    "Wnck": "3.0",
}


@dataclass(frozen=True)
class ImportUse:
    moduleName: str
    filePath: str
    lineNumber: int
    usageKind: str


class ImportCollector(ast.NodeVisitor):
    def __init__(self, sourcePath: Path) -> None:
        self.sourcePath = sourcePath
        self.parentMap: dict[ast.AST, ast.AST] = {}
        self.imports: list[ImportUse] = []

    def visit(self, node: ast.AST) -> Any:
        for childNode in ast.iter_child_nodes(node):
            self.parentMap[childNode] = node
        return super().visit(node)

    def visit_Import(self, node: ast.Import) -> None:
        usageKind = self._classify_usage(node)
        for aliasNode in node.names:
            self.imports.append(
                ImportUse(
                    moduleName=aliasNode.name,
                    filePath=str(self.sourcePath),
                    lineNumber=node.lineno,
                    usageKind=usageKind,
                )
            )

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        if node.level:
            return
        if not node.module:
            return

        usageKind = self._classify_usage(node)
        if node.module == "gi.repository":
            for aliasNode in node.names:
                self.imports.append(
                    ImportUse(
                        moduleName=f"gi.repository.{aliasNode.name}",
                        filePath=str(self.sourcePath),
                        lineNumber=node.lineno,
                        usageKind=usageKind,
                    )
                )
            return

        self.imports.append(
            ImportUse(
                moduleName=node.module,
                filePath=str(self.sourcePath),
                lineNumber=node.lineno,
                usageKind=usageKind,
            )
        )

    def _classify_usage(self, node: ast.AST) -> str:
        currentNode: ast.AST | None = node
        while currentNode is not None:
            parentNode = self.parentMap.get(currentNode)
            if parentNode is None:
                break
            if isinstance(parentNode, ast.If) and self._is_type_checking_guard(parentNode):
                return "type_only"
            if isinstance(parentNode, ast.Try) and currentNode in parentNode.body:
                if self._try_has_import_fallback(parentNode):
                    return "optional"
            currentNode = parentNode
        return "required"

    @staticmethod
    def _is_type_checking_guard(node: ast.If) -> bool:
        testNode = node.test
        if isinstance(testNode, ast.Name):
            return testNode.id == "TYPE_CHECKING"
        if isinstance(testNode, ast.Attribute):
            return testNode.attr == "TYPE_CHECKING"
        return False

    @staticmethod
    def _try_has_import_fallback(node: ast.Try) -> bool:
        if not node.handlers:
            return False
        for handlerNode in node.handlers:
            if handlerNode.type is None:
                return True
            if isinstance(handlerNode.type, ast.Name):
                if handlerNode.type.id in {
                    "Exception",
                    "ImportError",
                    "ModuleNotFoundError",
                    "BaseException",
                }:
                    return True
            if isinstance(handlerNode.type, ast.Tuple):
                for elementNode in handlerNode.type.elts:
                    if isinstance(elementNode, ast.Name) and elementNode.id in {
                        "Exception",
                        "ImportError",
                        "ModuleNotFoundError",
                        "BaseException",
                    }:
                        return True
        return False


def find_local_roots(sourceRoot: Path) -> set[str]:
    localRoots: set[str] = set()
    srcRoot = sourceRoot / "src"
    if not srcRoot.exists():
        return localRoots

    for childPath in srcRoot.iterdir():
        if childPath.is_file() and childPath.suffix == ".py":
            localRoots.add(childPath.stem)
        elif childPath.is_dir() and (childPath / "__init__.py").exists():
            localRoots.add(childPath.name)
    return localRoots


def iter_python_files(sourceRoot: Path) -> list[Path]:
    searchRoots = [sourceRoot / "src"]
    pythonFiles: list[Path] = []
    for searchRoot in searchRoots:
        if not searchRoot.exists():
            continue
        for sourcePath in searchRoot.rglob("*"):
            if not sourcePath.is_file():
                continue
            if sourcePath.suffix == ".py" or sourcePath.name.endswith(".py.in"):
                pythonFiles.append(sourcePath)
    return sorted(pythonFiles)


def normalize_module(moduleName: str) -> str:
    if moduleName.startswith("gi.repository."):
        return moduleName
    return moduleName.split(".")[0]


def is_stdlib_module(moduleName: str) -> bool:
    if moduleName == "__future__":
        return True
    rootName = moduleName.split(".")[0]
    return rootName in sys.stdlib_module_names


def scan_imports(sourceRoot: Path) -> tuple[dict[str, list[ImportUse]], list[dict[str, Any]]]:
    localRoots = find_local_roots(sourceRoot)
    groupedImports: dict[str, list[ImportUse]] = defaultdict(list)
    parseErrors: list[dict[str, Any]] = []

    for sourcePath in iter_python_files(sourceRoot):
        try:
            sourceText = sourcePath.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            sourceText = sourcePath.read_text(encoding="utf-8", errors="replace")

        try:
            tree = ast.parse(sourceText, filename=str(sourcePath))
        except SyntaxError as error:
            parseErrors.append(
                {
                    "file": str(sourcePath),
                    "line": error.lineno,
                    "message": error.msg,
                }
            )
            continue

        collector = ImportCollector(sourcePath)
        collector.visit(tree)
        for importUse in collector.imports:
            normalizedName = normalize_module(importUse.moduleName)
            rootName = normalizedName.split(".")[0]
            if rootName in localRoots:
                continue
            if is_stdlib_module(normalizedName):
                continue
            groupedImports[normalizedName].append(importUse)

    return dict(sorted(groupedImports.items())), parseErrors


def check_importable(moduleName: str) -> tuple[bool, str | None]:
    if moduleName.startswith("gi.repository."):
        return check_gi_module(moduleName)

    try:
        spec = importlib.util.find_spec(moduleName)
    except Exception as error:
        return False, f"{type(error).__name__}: {error}"
    if spec is None:
        return False, f"Module spec not found for {moduleName}"
    return True, None


def check_gi_module(moduleName: str) -> tuple[bool, str | None]:
    namespaceName = moduleName.rsplit(".", 1)[-1]
    try:
        import gi
        versionText = giVersions.get(namespaceName)
        if versionText:
            gi.require_version(namespaceName, versionText)
        importlib.import_module(moduleName)
        return True, None
    except Exception as error:
        return False, f"{type(error).__name__}: {error}"


def build_repo_index(repoRoot: Path) -> set[str]:
    packageNames: set[str] = set()
    for sectionName in repoRoot.iterdir():
        if not sectionName.is_dir():
            continue
        if sectionName.name.startswith("."):
            continue
        for childPath in sectionName.iterdir():
            if childPath.is_dir():
                packageNames.add(childPath.name)
    return packageNames


def summarize_usage(importUses: list[ImportUse]) -> str:
    usageKinds = {importUse.usageKind for importUse in importUses}
    if "required" in usageKinds:
        return "required"
    if "optional" in usageKinds:
        return "optional"
    return "type_only"


def find_package_hits(moduleName: str, repoPackages: set[str]) -> list[str]:
    candidates = packageHints.get(moduleName, [])
    return [candidate for candidate in candidates if candidate in repoPackages]


def build_report(sourceRoot: Path, repoRoot: Path) -> dict[str, Any]:
    groupedImports, parseErrors = scan_imports(sourceRoot)
    repoPackages = build_repo_index(repoRoot)
    modules: list[dict[str, Any]] = []

    for moduleName, importUses in groupedImports.items():
        importable, errorText = check_importable(moduleName)
        packageHits = find_package_hits(moduleName, repoPackages)
        exampleLocations = sorted(
            {f"{importUse.filePath}:{importUse.lineNumber}" for importUse in importUses}
        )
        modules.append(
            {
                "module": moduleName,
                "usage": summarize_usage(importUses),
                "importable": importable,
                "error": errorText,
                "packageHints": packageHints.get(moduleName, []),
                "packageHits": packageHits,
                "uses": len(importUses),
                "locations": exampleLocations,
            }
        )

    return {
        "sourceRoot": str(sourceRoot),
        "repoRoot": str(repoRoot),
        "modules": modules,
        "parseErrors": parseErrors,
    }


def print_text_report(reportData: dict[str, Any]) -> None:
    print(f"Source root: {reportData['sourceRoot']}")
    print(f"Repo root:   {reportData['repoRoot']}")
    print(f"Modules:     {len(reportData['modules'])}")
    print(f"Parse errors:{len(reportData['parseErrors'])}")
    print()
    print("Status  Usage      Module                          Slint package hits")
    print("------  ---------  ------------------------------  ----------------------------")

    for moduleData in reportData["modules"]:
        statusText = "ok" if moduleData["importable"] else "missing"
        packageText = ", ".join(moduleData["packageHits"]) or "-"
        print(
            f"{statusText:<6}  "
            f"{moduleData['usage']:<9}  "
            f"{moduleData['module']:<30}  "
            f"{packageText}"
        )

    if reportData["parseErrors"]:
        print()
        print("Parse errors:")
        for errorData in reportData["parseErrors"]:
            print(
                f"- {errorData['file']}:{errorData['line']}: "
                f"{errorData['message']}"
            )

    print()
    print("Missing modules:")
    missingModules = [moduleData for moduleData in reportData["modules"] if not moduleData["importable"]]
    if not missingModules:
        print("- none")
    else:
        for moduleData in missingModules:
            packageText = ", ".join(moduleData["packageHits"] or moduleData["packageHints"]) or "-"
            firstLocation = moduleData["locations"][0] if moduleData["locations"] else "-"
            print(
                f"- {moduleData['module']} ({moduleData['usage']})"
                f" -> {packageText}"
                f" [{firstLocation}]"
            )
            if moduleData["error"]:
                print(f"  {moduleData['error']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit Cthulhu Python imports against the local environment and Slint package tree."
    )
    parser.add_argument(
        "sourceRoot",
        nargs="?",
        default=str(DEFAULT_SOURCE_ROOT),
        help="Path to the Cthulhu source tree (default: %(default)s)",
    )
    parser.add_argument(
        "--repo-root",
        default=str(DEFAULT_REPO_ROOT),
        help="Path to the slackbuilds repo root (default: %(default)s)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the report as JSON.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sourceRoot = Path(args.sourceRoot).resolve()
    repoRoot = Path(args.repo_root).resolve()

    if not (sourceRoot / "src").exists():
        print(f"Source tree not found: {sourceRoot}", file=sys.stderr)
        return 1
    if not repoRoot.exists():
        print(f"Repo root not found: {repoRoot}", file=sys.stderr)
        return 1

    reportData = build_report(sourceRoot, repoRoot)
    if args.json:
        print(json.dumps(reportData, indent=2, sort_keys=True))
    else:
        print_text_report(reportData)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
