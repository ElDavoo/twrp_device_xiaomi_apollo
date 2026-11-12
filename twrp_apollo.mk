# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

PRODUCT_PLATFORM := kona
DEVICE_PATH := device/xiaomi/apollo

$(call inherit-product, vendor/twrp/config/common.mk)

PRODUCT_DEVICE := apollo
PRODUCT_NAME := twrp_apollo
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Mi 10T Pro
PRODUCT_MANUFACTURER := Xiaomi

$(call inherit-product, $(DEVICE_PATH)/device.mk)
