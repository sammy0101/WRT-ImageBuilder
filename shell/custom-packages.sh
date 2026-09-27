#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (官方原版英文介面)
# ==============================================================================

CUSTOM_PACKAGES=""

# 核心 Web UI
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# 介面主題
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# 依賴組件
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ca-bundle kmod-tun"

# 若需要代理，原版 OpenWrt 推薦使用 OpenClash 或 PassWall (不需要內核 BTF)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

export CUSTOM_PACKAGES
