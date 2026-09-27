#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (極簡原生英文版，不含任何多餘依賴)
# ==============================================================================

CUSTOM_PACKAGES=""

# 1. 核心 Web 管理介面 (官方原生英文)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# 2. 介面美化主題 (若連主題都不想要、想用官方預設 Bootstrap 主題，可在該行開頭加 #)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# ==============================================================================
# 常用可選組件 (按需取消「#」號啟用即可)
# ==============================================================================
# --- 代理客戶端 (原版 OpenWrt 推薦) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# --- 網路與系統工具 ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wireguard"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-zerotier"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4"

export CUSTOM_PACKAGES
