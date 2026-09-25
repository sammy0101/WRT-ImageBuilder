#!/usr/bin/env bash
# ==============================================================================
# 極簡純淨版配置：不包含任何第三方外掛，使用官方原生主題
# 僅保留 LuCI Web 管理介面與繁體中文語系
# ==============================================================================

CUSTOM_PACKAGES=""

# 1. 核心網頁管理介面 (確保官方原版 OpenWrt 與 ImmortalWrt 開機即有 Web 後台)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# 2. 繁體中文語系支援 (涵蓋系統管理、介面與防火牆選單)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-tw"

# ==============================================================================
# 已移除所有額外第三方插件 (保持 100% 官方純淨狀態):
# - 不安裝自訂主題 (維持官方預設 Bootstrap 主題)
# - 不安裝 ttyd, autoreboot, diskman, upnp, wol
# - 不安裝 curl, wget, htop, lsblk 等額外除錯工具
# ==============================================================================

export CUSTOM_PACKAGES
