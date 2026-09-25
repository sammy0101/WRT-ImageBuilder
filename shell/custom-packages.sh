#!/usr/bin/env bash
# ==============================================================================
# 自訂額外軟體包選單 (可在此處透過加減號註解自由取捨)
# 帶有 "-" 號代表從底包移除該插件，無減號代表安裝
# ==============================================================================

CUSTOM_PACKAGES=""

# ---------- 繁體中文 LuCI 語系支援 ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-opkg-zh-tw"

# ---------- 外觀主題 ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# ---------- 常用網路與系統管理 (預設啟用) ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot luci-i18n-autoreboot-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp luci-i18n-upnp-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol luci-i18n-wol-zh-tw"

# ---------- 磁碟與檔案傳輸 ----------
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman luci-i18n-diskman-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget htop lsblk fdisk e2fsprogs"

# ---------- 效能加速與網路優化 (按需啟用，去除前綴 # 即可) ----------
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc luci-i18n-turboacc-zh-tw"

# ---------- 檔案共用 Samba ----------
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4 luci-i18n-samba4-zh-tw"

# ---------- 旁路由/特殊網路工具 ----------
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

export CUSTOM_PACKAGES
