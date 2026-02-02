In this document we present the scripts shipped in Slint that allow
booting Slint just after installation as after a kernel upgrade, and
optionally bringing portability to Slint.

1. grubconfig

This script installs and configure grub in a newly installed Slint, to
allow booting it.

It installs if possible grub in both Legacy and UEFI modes, for more
flexibility. This needs to set up an EFI system partition (ESP) on the
device where Slint is installed, even if the machine boots the installer
in Legacy mode. An ESP is mandatory if the machine can only boot in EFI
mode.

If the machine is in UEFI mode when installing, grubconfig proposes
to install a boot entry for Slint in the machine's firmware boot menu,
in addition to the boot image installed in the ESP.

3. update-portable

This script brings portability to an already installed Slint as if it
was set up this way at time of installation.

If the system is already portable, it is run transparently by the script
upgrade-kernel (see below) to update the initrd and the custom grub
configuration file grub.conf.

If you prefer to switch or go back to a non-portable Slint, just run
the script update-grub (see below).

You can switch between portable and non-portable at libitum.

4. upgrade-kernel

This script applies an upgrade of kernel package provided by Slint:
- upgrading these packages,
- making an initrd with support for all the installed generic kernels,
- and updating the GRUB configuration file grub.cfg, running either
  update-portable or update-grub for a portable or non-portable Slint.

5. update-grub

This script backs up the existing configuration file grub.cfg then
makes and installs a new one, running the grub-mkconfig utility shipped
in the GRUB package.
