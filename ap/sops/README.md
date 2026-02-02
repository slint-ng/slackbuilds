SOPS — Simple Orca Plugin System
===================================

SOPS provides a simple way to write custom plugins for screen reader Orca. It
requires Orca to be installed.

Documentation And Usage
-----------------------

For usage in Slint, cf. the web page usage.html alongside this one.

The full documentation can be found in the Arch wiki at
https://wiki.archlinux.org/index.php/Simple_Orca_Plugin_System

Ignore the Installation paragraph as SOPS is already installed in your
Slint system if you read this file.

Uninstallation
--------------

-   Type as root: removepkg sops
-   remove user-local installation:

        rm -r ~/.config/SOPS # remove the userplugins and the configuration

    -   remove the following section from file `~/.local/share/orca/orca-customizations.py` :

    ```python
    # Start SimpleOrcaPluginLoader DO NOT TOUCH!
    import os
    import importlib.util
    spec = importlib.util.spec_from_file_location('SimplePluginLoader', os.path.expanduser('~')+'/.config/SOPS/SimplePluginLoader.py')
    SimplePluginLoaderModule = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(SimplePluginLoaderModule)
    # End SimpleOrcaPluginLoader DO NOT TOUCH!
    ```


