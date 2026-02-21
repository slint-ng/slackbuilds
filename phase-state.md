# Phase State

## Phase 2 Completed and Validated
1. `k/amd-microcode`
2. `k/firmware-installer` (renamed from `k/kernel-firmware-installer`)

## Phase 3 Completed and Validated
1. `k/kernel` (now split across `k/kernel`, `k/kernel-headers`, `k/kernel-source`)
2. `k/modules-installer` (replaces legacy helper script contract)
3. `a/kernel-firmware` (converted in place, no move)

## Phase 1 Completed and Validated
1. `k/intel-microcode`
2. `k/dkms`
3. `k/iucode_tool`
4. `k/sof-firmware`
5. `k/b43-firmware`
6. `n/zd1211-firmware`

## Marker
- Validation skill added and committed: `c1b874e`
- Installer package naming aligned with published artifact: `firmware-installer`
- AMD microcode remains authoritative in: `k/amd-microcode`
- Phase 3 validation completed on 2026-02-21 for:
  `k/kernel`, `k/kernel-headers`, `k/kernel-source`,
  `k/modules-installer`, `a/kernel-firmware`,
  `k/amd-microcode`, and `k/firmware-installer`.
- Upgrade prep updated on 2026-02-21:
  `k/kernel*` and `k/modules-installer` -> `6.19.3`,
  linux-firmware snapshot -> `20260110_06a743f`,
  `k/dkms` -> `3.3.0`,
  `k/intel-microcode` -> `20260210`,
  `k/sof-firmware` -> `2025.12.2`.
- DKMS compatibility restored on 2026-02-21:
  `k/dkms` now keeps legacy helpers under `/usr/lib/dkms/`
  (`dkms_autoinstaller` and `common.postinst`).
- Runtime rollout verified on 2026-02-21:
  host boots kernel `6.19.3`, early microcode images are present in `/boot`,
  and `dkms status` is empty (no DKMS modules installed).
