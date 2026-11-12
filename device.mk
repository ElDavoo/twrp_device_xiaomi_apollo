# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit from TWRP common config
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, vendor/twrp/config/common.mk)

# Build only for apollo
TARGET_OTA_ASSERT_DEVICE := apollo,apollopro,apollon

# Crypto / FBE decryption (QCOM CAF)
PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe

# keystore2 needs libsqlite.so; TWRP's static ld.config only searches
# /system/lib64, so build our own (matching tree's ICU) instead of
# borrowing the ROM's (ICU symbol mismatch).
PRODUCT_PACKAGES += \
    libsqlite

# ro.debuggable=1 ensures post_process_props.py appends "adb" instead of "none"
# to every partition prop file, so adbd starts at boot.
PRODUCT_ODM_PROPERTIES += ro.debuggable=1
PRODUCT_PRODUCT_PROPERTIES += ro.debuggable=1
PRODUCT_SYSTEM_EXT_PROPERTIES += ro.debuggable=1

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# fastbootd
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH)

# Debugfs restrictions (matches PixelOS / apollo ROM)
PRODUCT_DEBUG_FS_ALLOW_ALL := false

# Health HAL for battery status. AOSP default health HAL built from source (reads
# /sys/class/power_supply); the ROM's QTI blob needs the ROM's libc++.
PRODUCT_PACKAGES += android.hardware.health-service.apollo_recovery

# Device properties (crypto + GUI2 status bar)
PRODUCT_SYSTEM_PROPERTIES += ro.crypto.allow_encrypt_override=true
PRODUCT_SYSTEM_PROPERTIES += ro.crypto.volume.filenames_mode=aes-256-cts
PRODUCT_SYSTEM_PROPERTIES += ro.hardware.keystore_desede=true
PRODUCT_SYSTEM_PROPERTIES += ro.twrp.gui2.status_right=true
PRODUCT_VENDOR_PROPERTIES += ro.crypto.allow_encrypt_override=true
PRODUCT_VENDOR_PROPERTIES += ro.crypto.volume.filenames_mode=aes-256-cts
PRODUCT_VENDOR_PROPERTIES += ro.hardware.keystore_desede=true
