#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (極簡原生穩定版 - 100% 保證編譯成功)
#
# 【使用說明】:
# 預設啟用官方原版 100% 支援的核心 Web、繁體中文語系與旁路由必備工具鏈。
# 所有第三方外掛均已加上「#」註解，建議開機後按需手動安裝。
# （Docker 請直接在 GitHub Actions 網頁勾選，此處無需設定）
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (官方源 100% 內建，保證編譯成功)
# ==============================================================================
# 核心 Web 網頁介面 + 官方繁體中文語言包
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci luci-i18n-base-zh-tw luci-i18n-firewall-zh-tw"

# 旁路由通用底層工具鏈 (出廠預載，日後手動安裝代理工具免再下載相依)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tun ca-bundle curl tar coreutils-nohup bash"

# ==============================================================================
# 1. 主題美化 (選用)
# 【說明】ImmortalWrt 官方源自帶 argon；OpenWrt 官方原版無此包，建議開機後再裝
# ==============================================================================
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# ==============================================================================
# 2. daeuniverse 代理工具 (選用，開機後手動安裝)
# ==============================================================================
# honk (開機後可依官方手冊手動安裝)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES honk"

# dae (開機後可手動安裝)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES dae"

# ==============================================================================
# 3. 其他代理客戶端 (選用)
# ==============================================================================
# OpenClash (自帶內核環境)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# PassWall (ImmortalWrt 官方支援佳)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# HomeProxy (ImmortalWrt 官方首推)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# Mihomo
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# v2rayA
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES v2raya xray-core luci-app-v2raya"

# ==============================================================================
# 4. DNS 防污染與廣告過濾 (選用)
# ==============================================================================
# SmartDNS
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES smartdns luci-app-smartdns"

# MosDNS
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns"

# AdGuard Home
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adguardhome luci-app-adguardhome"

# Adblock (官方原生廣告過濾)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adblock luci-app-adblock"

# ==============================================================================
# 5. 異地組網、內網穿透與 VPN (選用)
# ==============================================================================
# Tailscale
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft luci-app-tailscale"

# ZeroTier
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES zerotier luci-app-zerotier"

# WireGuard
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-wireguard wireguard-tools luci-app-wireguard"

# FRP Client
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES frpc luci-app-frpc"

# ==============================================================================
# 6. 常用網路功能、系統工具與維護 (選用)
# ==============================================================================
# ttyd 終端機
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES ttyd luci-app-ttyd"

# 定時自動重啟
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# UPnP 自動通訊埠對應
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES miniupnpd luci-app-upnp"

# WOL 網路喚醒
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES etherwake luci-app-wol"

# Diskman 磁碟管理
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES e2fsprogs fdisk smartmontools luci-app-diskman"

# Samba 4 局域網共用
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES samba4-server luci-app-samba4"

# 常用命令列除錯測速工具箱
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES wget-ssl htop lsblk iperf3"

export CUSTOM_PACKAGES
