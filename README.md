# YARP device tree for Xiaomi Mi 10T Pro / Mi 10T / Redmi K30S Ultra (apollo)

Unofficial **YARP** (Yet Another Recovery Project) for **apollo / apollon**.

YARP is the recovery developed in the [TWRP-Test](https://github.com/TWRP-Test) organization on the
`twrp-16.0` branch. It forked from TWRP and replaces TWRP's interface with an LVGL interface called `gui2`.
It still uses TWRP's build system, so some names below say "twrp":

- the `vendor/twrp` config, the `twrp_apollo` lunch target, the `TW_*` build flags and the `ro.twrp.*` properties
- the `twrp` command-line tool
- the 3.7.1_16-0 version string

This is **not** an official TWRP build. Please don't report its bugs to TeamWin.

It targets current custom ROMs on Android 16/17. It was developed and tested on **LineageOS 24.0 (Android 17)**.

> Unofficial. Test with `fastboot boot` before you flash. Keep a copy of your current recovery.

## Status

Tested on M2007J3SG with LineageOS 24.0, FBE plus metadata encryption, hardware-wrapped keys, and a PIN:

| Feature | Status |
| --- | --- |
| Boot, touch, adb | ✅ |
| Dynamic partitions: system / system_ext / product (ext4) and vendor / odm (**erofs**) | ✅ |
| `/data` metadata decryption (dm-default-key, legacy format, hardware-wrapped key) | ✅ |
| FBE user 0 unlock with **PIN**; YARP asks for a PIN, not a password | ✅ |
| Internal storage (`/sdcard`) after decrypt | ✅ |
| Battery level, using AOSP's health HAL built from source | ✅ |
| Status bar on the right, clear of the top-left punch hole | ✅ |
| Installing LineageOS zips, with `addon.d` backup/restore | ✅ (lineage-24.0-20261107 nightly; see below) |
| Zips cannot overwrite YARP (recovery partition write guard) | ✅ |
| Zips cannot overwrite the boot partition / kernel (boot write guard, r3) | ✅ |
| Pattern / password credentials | same code path as PIN, not tested on device |
| ROMs that run the SPU (`spdaemon`, e.g. possibly stock MIUI) | untested |
| ROM security-patch update (2026-10 → 2026-11) without rebuilding recovery | ✅ |
| Backup / restore, MTP, sideload | untested |

## Install

Test it first without changing anything on the phone:

```bash
fastboot boot yarp-*.img
```

To install it permanently:

```bash
fastboot flash recovery yarp-*.img
fastboot reboot recovery
```

### Keeping YARP when you update LineageOS

LineageOS zips for apollo **always flash their own `recovery.img`** as the last step of the
updater script. This build blocks that inside YARP itself, with **Settings → General → "Protect
recovery partition during zip install"**, which is on by default:

- Before a zip runs, YARP snapshots the recovery partition and makes its block device read-only
  (`BLKROSET`). Every write path fails: edify `package_extract_file`, `dd` from scripts,
  `/dev/block/by-name/recovery` or the raw `sdXN` node. LineageOS's updater ignores that step's
  result, so the rest of the update installs normally.
- Afterwards YARP clears the flag and compares the partition with the snapshot. If a zip changed
  it anyway, for example by clearing the read-only flag itself, the snapshot is written back and
  the install log says so.

The same guard covers the **boot partition** (kernel, or a KernelSU/custom-kernel boot image) with
**"Protect boot partition (kernel) during zip install"**, also on by default. A ROM update then keeps
your kernel instead of replacing it with the stock one. Turn it off when you want a zip to update the kernel.

Turn the recovery setting off when you *do* want a zip to install a recovery. Flashing an image from
YARP's image-flash screen, or with `fastboot flash recovery`, is not affected.

`tools/strip_recovery_from_ota.py` still works if you'd rather keep the step out of the zip. With
`persist.vendor.recovery_update=false`, the default under Developer options → "Update recovery",
the ROM never rewrites recovery when Android boots.

## How decryption is set up

Most of what makes `/data` work happens at boot, in `recovery/root/system/bin/prepare-crypto.sh`.
The script mounts the installed ROM's system and vendor partitions read-only and copies its values into recovery:

- `ro.build.version.release`, `ro.build.version.security_patch`, `ro.vendor.build.security_patch`.
  These are the version binding inputs that keymaster checks.
- `ro.product.first_api_level`, which falls back to 29 because apollo shipped with Android 10.
  vold uses this value to choose the legacy or v2 dm-default-key format, the hardware-wrapped
  metadata key and the FBE policy version. YARP's default of 10000 picks v2. The 463-byte keymaster
  blob is then passed as the key and dm-default-key fails with "Invalid keysize".
- Any `ro.crypto.*` options the ROM sets, and `vendor.gatekeeper.disable_spu`.
- `vendor.gatekeeper.disable_spu=true` is set whenever the ROM has no `spdaemon`. The QTI gatekeeper
  HAL first probes the SPU (secure processor). Without SPSS firmware, the probe waits 30 s and the
  PIN verify then fails with -45. The ROM's enforcing SELinux policy never lets gatekeeper reach the
  SPU, so the PIN lives in the QSEE TA.

The script then sets `crypto.ready=1`, which starts keymaster 4.0 and gatekeeper 1.0. Both are the
ROM's QTI blobs, pulled with `tools/extract_blobs.sh`. The recovery's boot header keeps YARP's
`99.87.36` / `2099-12`. As a result, key blobs are only upgraded in memory (KEY_REQUIRES_UPGRADE),
nothing is written back, and the recovery keeps working after ROM security updates.

## Building

```bash
repo init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0 --depth=1
repo sync -c --no-tags
git clone https://github.com/ElDavoo/twrp_device_xiaomi_apollo device/xiaomi/apollo

# proprietary keymaster/gatekeeper/qseecom blobs are not tracked: pull them from a
# phone running the ROM (or from YARP with /vendor mounted)...
device/xiaomi/apollo/tools/extract_blobs.sh
# ...or extract them from a LineageOS apollon OTA zip (needs brotli and erofs-utils)
device/xiaomi/apollo/tools/blobs_from_ota.sh lineage-*-apollon-signed.zip

# source patches (see patches/)
git -C bootable/recovery am "$PWD"/device/xiaomi/apollo/patches/bootable_recovery/*.patch
git -C system/vold      am "$PWD"/device/xiaomi/apollo/patches/system_vold/*.patch

export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_apollo-bp2a-eng
mka recoveryimage
```

### GitHub Actions

`.github/workflows/build.yml` builds the image on GitHub (Actions → Build YARP recovery → Run workflow).
It syncs YARP, applies `patches/`, takes the vendor blobs from the latest LineageOS apollon nightly
(or the OTA URL you give it), and uploads `recovery.img` as an artifact. ccache is kept in the
Actions cache, so later builds are much faster. If a cold build hits the time limit, run it again
and it continues from the saved ccache. Set `release_tag` to publish a release with the image.

### Patches

- `bootable_recovery/0001`: mount erofs read-only. A read-write mount fails with EACCES, so vendor and odm never mounted.
- `bootable_recovery/0002`: `ro.twrp.gui2.status_right=true` moves the clock to the right side of the status bar.
- `bootable_recovery/0003`: recovery partition write guard during zip installs. Adds the `tw_protect_recovery` setting, on by default, translated for en, ru, zh_CN and zh_TW.
- `bootable_recovery/0004`: the same guard for the boot partition, with the `tw_protect_boot` setting (on by default).
- `system_vold/0001`: honor `ro.crypto.dm_default_key.options_format.version` like AOSP and LineageOS do,
  and log the default-key key sizes. No key material is logged.

## Credits

- [TWRP-Test / YARP](https://github.com/TWRP-Test) for the recovery sources, and TeamWin for TWRP, which YARP is based on.
- [Kazurin-775/twrp_device_xiaomi_gauguin](https://github.com/Kazurin-775/twrp_device_xiaomi_gauguin), the base for this tree's layout and crypto setup.
- [NutellaSimpDev/twrp_device_xiaomi_apollo](https://github.com/NutellaSimpDev/twrp_device_xiaomi_apollo) for the prebuilt kernel, dtb and dtbo (4.19, erofs-enabled).
- [1337heker/twrp_device_xiaomi_apollo](https://github.com/1337heker/twrp_device_xiaomi_apollo) and TeamWin's apollo and sm8250 trees, used as references.
- Proprietary blobs in `recovery/root/vendor` come from the LineageOS apollo vendor image.
