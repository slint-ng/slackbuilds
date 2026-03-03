#!/usr/bin/env python3

import importlib
import importlib.util


dependencies = [
    "gi",
    "gi.repository.Atk",
    "gi.repository.Atspi",
    "gi.repository.GLib",
    "gi.repository.GObject",
    "gi.repository.Gdk",
    "gi.repository.GdkPixbuf",
    "gi.repository.Gio",
    "gi.repository.Gst",
    "gi.repository.Gtk",
    "gi.repository.Pango",
    "gi.repository.Wnck",
    "pluggy",
    "tomlkit",
    "brlapi",
    "speechd",
    "piper",
    "louis",
    "dasbus",
    "psutil",
    "cairo",
    "requests",
    "pyautogui",
    "msgpack",
    "tornado",
    "Xlib",
    "PIL",
    "pytesseract",
    "pdf2image",
    "scipy",
    "webcolors",
]


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


packageHints = {
    "gi": "pygobject3.11 or pygobject3",
    "gi.repository.Atk": "atk",
    "gi.repository.Atspi": "python-atspi and at-spi2-core",
    "gi.repository.GLib": "glib2",
    "gi.repository.GObject": "glib2",
    "gi.repository.Gdk": "gtk+3",
    "gi.repository.GdkPixbuf": "gdk-pixbuf2",
    "gi.repository.Gio": "glib2",
    "gi.repository.Gst": "gstreamer gst-plugins-base gst-plugins-good",
    "gi.repository.Gtk": "gtk+3",
    "gi.repository.Pango": "pango",
    "gi.repository.Wnck": "libwnck3",
    "pluggy": "python3-pluggy",
    "tomlkit": "python3-tomlkit or python-tomlkit",
    "brlapi": "brltty",
    "speechd": "speech-dispatcher3.11 or speech-dispatcher",
    "piper": "piper-tts",
    "louis": "liblouis",
    "dasbus": "python3-dasbus",
    "psutil": "psutil3.11 or psutil",
    "cairo": "pycairo3.11 or pycairo",
    "requests": "python-requests",
    "pyautogui": "python3-pyautogui",
    "msgpack": "python3-msgpack",
    "tornado": "python3-tornado",
    "Xlib": "python3-xlib or python-xlib",
    "PIL": "python3-pillow",
    "pytesseract": "python-pytesseract",
    "pdf2image": "python-pdf2image",
    "scipy": "python-scipy",
    "webcolors": "python-webcolors",
}


def check_dependency(moduleName):
    try:
        if moduleName.startswith("gi.repository."):
            import gi

            namespaceName = moduleName.rsplit(".", 1)[-1]
            version = giVersions.get(namespaceName)
            if version:
                gi.require_version(namespaceName, version)

            importlib.import_module(moduleName)
            print(f"{moduleName}: ok")
            return True

        moduleSpec = importlib.util.find_spec(moduleName)
        if moduleSpec is None:
            raise ModuleNotFoundError(f"No module named '{moduleName}'")

        print(f"{moduleName}: ok")
        return True
    except Exception as error:
        packageName = packageHints.get(moduleName, "unknown package")
        print(f"{moduleName}: missing ({packageName})")
        print(f"  {type(error).__name__}: {error}")
        return False


def main():
    missingCount = 0
    for moduleName in dependencies:
        if not check_dependency(moduleName):
            missingCount += 1

    print()
    print(f"Checked {len(dependencies)} dependencies, missing {missingCount}.")


if __name__ == "__main__":
    main()
