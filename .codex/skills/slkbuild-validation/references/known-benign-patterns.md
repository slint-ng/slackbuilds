# Known Benign Log Patterns

These patterns are treated as non-fatal by the validator when package creation
success markers and artifacts are present.

1. `ALSA lib ... tplg_build_routes ... undefined source/sink`
- Seen in `sof-firmware` topology generation.
- Does not block package output.

2. `rmdir: failed to remove ... usr/doc ... No such file or directory`
- Seen during link/script generation in `zd1211-firmware` packaging.
- Does not block package output.

