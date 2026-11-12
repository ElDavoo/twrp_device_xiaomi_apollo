#!/system/bin/sh

# Sets crypto-critical properties from the ROM's build.props, then signals the
# crypto chain (crypto.ready=1 -> init starts keymaster-4-0). Modeled on
# /odm/bin/prepdecrypt.sh from the reference tree.
#
# Synchronization with TWRP: the super mapper devices appear during
# Setup_Fstab_Partitions, and Decrypt_Data() then blocks in getService()
# for keymaster for up to 25 s. Finishing within that window means keymaster
# registers mid-wait with correct patchlevels already cached, and the single
# automatic metadata decrypt attempt succeeds.
#
# The two ro. patch props already exist in the ramdisk prop.default, and init
# rejects re-setting an existing ro. prop via setprop ("Read-only property
# was already set"), so resetprop is required for them.

TMP_MNT=/tmp/prepare-crypto
SYSTEM_DEV=/dev/block/mapper/system
VENDOR_DEV=/dev/block/mapper/vendor
RESETPROP=/system/bin/resetprop
[ -e "$RESETPROP" ] || RESETPROP=/sbin/resetprop

log_msg() {
    log -t prepare-crypto "$1"
}

i=0
while [ ! -e "$SYSTEM_DEV" ] || [ ! -e "$VENDOR_DEV" ]; do
    if [ $i -ge 60 ]; then
        log_msg "Mapper devices never appeared"
        setprop crypto.ready 1  # fail soft: keep the chain observable in logs
        exit 1
    fi
    sleep 0.5
    i=$((i + 1))
done

mkdir -p "$TMP_MNT/system" "$TMP_MNT/vendor"
if ! mount -o ro "$SYSTEM_DEV" "$TMP_MNT/system" || \
   ! mount -o ro "$VENDOR_DEV" "$TMP_MNT/vendor"; then
    log_msg "Temporary mounts of /system and /vendor failed"
    umount "$TMP_MNT/system"
    umount "$TMP_MNT/vendor"
    setprop crypto.ready 1
    exit 1
fi

# SAR layout: system build.prop lives under <mount>/system; vendor may be
# either flat or nested depending on image generation.
[ -f "$TMP_MNT/system/system/build.prop" ] && SYSTEM_PROP_FILE="$TMP_MNT/system/system/build.prop" \
    || SYSTEM_PROP_FILE="$TMP_MNT/system/build.prop"
[ -f "$TMP_MNT/vendor/system/build.prop" ] && VENDOR_PROP_FILE="$TMP_MNT/vendor/system/build.prop" \
    || VENDOR_PROP_FILE="$TMP_MNT/vendor/build.prop"

BUILD_PATCH=$(grep -E '^ro\.build\.version\.security_patch=' "$SYSTEM_PROP_FILE" | cut -d= -f2)
VENDOR_PATCH=$(grep -E '^ro\.vendor\.build\.security_patch=' "$VENDOR_PROP_FILE" | cut -d= -f2)
# ro.build.version.release feeds keymaster's OS_VERSION binding input. The
# ramdisk default (e.g. 99.87.36) parses higher than any real ROM release and
# makes the TA demand an upgrade of every key blob (Begin -> KEY_REQUIRES_UPGRADE).
RELEASE=$(grep -E '^ro\.build\.version\.release=' "$SYSTEM_PROP_FILE" | cut -d= -f2)
# vold and libfscrypt pick the dm-default-key options format (legacy v1 vs v2),
# hardware-wrapped metadata keys and the FBE policy version from the launch API
# level. The ramdisk default (10000 on unreleased-SDK trees) selects v2 and makes
# the metadata decrypt hand the raw key blob to dm-default-key ("Invalid keysize").
# apollo launched on Android 10, so 29 is the right fallback for any ROM.
FIRST_API=$(grep -hE '^ro\.product\.first_api_level=' "$VENDOR_PROP_FILE" "$SYSTEM_PROP_FILE" | head -n1 | cut -d= -f2)
[ -n "$FIRST_API" ] || FIRST_API=29

# Crypto knobs the installed ROM may set in its vendor props. Copy whatever it
# defines so the recovery follows the ROM instead of the values baked in at
# build time (different ROMs use different fstab/encryption layouts).
VENDOR_PROP_FILES="$VENDOR_PROP_FILE"
[ -f "$TMP_MNT/vendor/default.prop" ] && VENDOR_PROP_FILES="$VENDOR_PROP_FILES $TMP_MNT/vendor/default.prop"
ROM_PROPS=""
for prop in ro.crypto.volume.filenames_mode ro.crypto.volume.contents_mode \
            ro.crypto.volume.options ro.crypto.dm_default_key.options_format.version \
            ro.crypto.set_dun ro.crypto.allow_encrypt_override vendor.gatekeeper.disable_spu; do
    value=$(grep -h "^$prop=" $VENDOR_PROP_FILES | tail -n1 | cut -d= -f2-)
    [ -n "$value" ] && ROM_PROPS="$ROM_PROPS $prop=$value"
done

# The QTI gatekeeper HAL first probes the SPU (secure processor). ROMs without
# spdaemon never load the SPSS firmware, so there the probe waits 30 s and the
# verify then fails with -45; their credentials live in the QSEE TA, which is
# what the ROM itself uses. Only skip the SPU when the ROM does not run it.
case "$ROM_PROPS" in
    *vendor.gatekeeper.disable_spu=*) ;;
    *) [ -e "$TMP_MNT/vendor/bin/spdaemon" ] || ROM_PROPS="$ROM_PROPS vendor.gatekeeper.disable_spu=true" ;;
esac
umount "$TMP_MNT/system"
umount "$TMP_MNT/vendor"
rmdir "$TMP_MNT/system" "$TMP_MNT/vendor" "$TMP_MNT"

for kv in $ROM_PROPS; do
    "$RESETPROP" "${kv%%=*}" "${kv#*=}"
done

# setprop cannot change these (already exist as ro. props); resetprop can.
[ -n "$BUILD_PATCH" ] && "$RESETPROP" ro.build.version.security_patch "$BUILD_PATCH"
[ -n "$VENDOR_PATCH" ] && "$RESETPROP" ro.vendor.build.security_patch "$VENDOR_PATCH"
[ -n "$RELEASE" ] && "$RESETPROP" ro.build.version.release "$RELEASE"
[ -n "$FIRST_API" ] && "$RESETPROP" ro.product.first_api_level "$FIRST_API"

# Keep the ramdisk prop.default in sync for anything that re-reads it.
if [ -f /prop.default ]; then
    [ -n "$BUILD_PATCH" ] && sed -i "s/ro.build.version.security_patch=.*/ro.build.version.security_patch=$BUILD_PATCH/g" /prop.default
    [ -n "$VENDOR_PATCH" ] && sed -i "s/ro.vendor.build.security_patch=.*/ro.vendor.build.security_patch=$VENDOR_PATCH/g" /prop.default
    [ -n "$RELEASE" ] && sed -i "s/ro.build.version.release=.*/ro.build.version.release=$RELEASE/g" /prop.default
    [ -n "$FIRST_API" ] && sed -i "s/ro.product.first_api_level=.*/ro.product.first_api_level=$FIRST_API/g" /prop.default
fi

log_msg "Set system=$BUILD_PATCH vendor=$VENDOR_PATCH release=$RELEASE first_api=$FIRST_API rom:$ROM_PROPS; set crypto.ready=1"
setprop crypto.ready 1
