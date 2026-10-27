#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (極簡原生英文版，出廠預載旁路由通用依賴)
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設啟用)
# ==============================================================================
# 核心 Web 網頁介面 (原生英文)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# Argon 現代自適應主題 + Argon 外觀配置管理後台
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon luci-app-argon-config"

# ==============================================================================
# 1. 旁路由通用執行環境與核心依賴 (出廠預載，免開機連網安裝)
# 完美相容 DAED (eBPF)、OpenClash (TUN/TPROXY)、PassWall 與 Shell 腳本
# ==============================================================================
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tun ca-bundle curl tar coreutils-nohup bash"

# ==============================================================================
# 2. 代理客戶端與科學上網 (按需解鎖)
# ==============================================================================
# OpenClash (基於 Clash.Meta / Mihomo 內核的進階代理工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# PassWall (經典穩定的代理工具，支援 Trojan/VLESS/Hysteria2/TUIC/SS)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# HomeProxy (ImmortalWrt 官方主推，基於 sing-box 的高效能透明代理)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# Mihomo (新一代輕量化 Clash.Meta 原生 LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# ==============================================================================
# 3. 常用網路功能、系統工具與維護
# ==============================================================================
# ttyd (直接在網頁後台開啟 Linux 終端機)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd"

# 定時自動重啟 (維持設備長時間穩定運行)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# UPnP 自動通訊埠對應
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp"

# WOL 網路喚醒
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol"

# Diskman 磁碟管理
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman"

export CUSTOM_PACKAGES
