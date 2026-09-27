#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (官方原版英文介面，不預裝繁體中文)
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (官方原版英文 Web UI)
# ==============================================================================
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# ==============================================================================
# 1. 代理 / 科學上網客戶端
# ==============================================================================
# DAED (已啟用：系統會自動直植入二進制與 LuCI 介面)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed"

# --- 其他可選代理外掛 (按需取消「#」號啟用) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-v2raya"

# ==============================================================================
# 2. 系統美化、VPN 與常用工具
# ==============================================================================
# Argon 現代主題 (已啟用)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# --- 其他常用工具 ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wireguard"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-zerotier"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4"

export CUSTOM_PACKAGES
