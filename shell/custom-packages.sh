#!/usr/bin/env bash
# ==============================================================================
# 自訂額外軟體包選單 (相容 23.05 / 24.10 / 25.12+ apk 架構)
# ==============================================================================

CUSTOM_PACKAGES=""

# ---------- 繁體中文 LuCI 語系支援 ----------
# 核心繁體中文介面 (base 與 firewall 已涵蓋系統絕大多數選單)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-tw"

# ---------- 外觀主題 ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# ---------- 常用網路與系統管理 (預設啟用) ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot" # autoreboot 已內建繁簡介面，無需獨立 zh-tw 包
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp luci-i18n-upnp-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol luci-i18n-wol-zh-tw"

# ---------- 磁碟與檔案傳輸 ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman luci-i18n-diskman-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget htop lsblk fdisk e2fsprogs"

# ---------- 效能加速與網路優化 (按需啟用，去除前綴 # 即可) ----------
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc"

# ---------- 檔案共用 Samba ----------
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4 luci-i18n-samba4-zh-tw"

export CUSTOM_PACKAGES
