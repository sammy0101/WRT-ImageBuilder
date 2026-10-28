#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (預載繁體中文與 Argon 現代主題)
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設一同安裝)
# ==============================================================================
# 核心 Web 網頁介面 + 官方繁體中文語言包
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci luci-i18n-base-zh-tw luci-i18n-firewall-zh-tw"

# Argon 現代自適應主題 (預設預裝)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# 旁路由通用底層工具鏈 (預先植入)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tun ca-bundle curl tar coreutils-nohup bash"

# ==============================================================================
# 1. daeuniverse 代理工具 (開機後手動安裝)
# ==============================================================================
# honk (開機後依官方教學手動安裝)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES honk"

# dae (開機後手動安裝)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES dae"

# ==============================================================================
# 2. 其他主流代理客戶端 (選用)
# ==============================================================================
# OpenClash (Clash.Meta / Mihomo 內核代理客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# PassWall (經典代理工具 + 常用組件)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# HomeProxy (ImmortalWrt 官方主推)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# Mihomo
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# v2rayA
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES v2raya xray-core luci-app-v2raya"

# ==============================================================================
# 3. DNS 防污染與廣告過濾 (選用)
# ==============================================================================
# SmartDNS
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES smartdns luci-app-smartdns"

# MosDNS
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns"

# AdGuard Home
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adguardhome luci-app-adguardhome"

# Adblock
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adblock luci-app-adblock"

# ==============================================================================
# 4. 異地組網、內網穿透與 VPN (選用)
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
# 5. 常用網路功能、系統工具與維護 (選用)
# ==============================================================================
# ttyd 網頁終端機
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES ttyd luci-app-ttyd"

# 定時自動重啟
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# UPnP 自動通訊埠對應
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES miniupnpd luci-app-upnp"

# WOL 網路喚醒
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES etherwake luci-app-wol"

# Diskman 磁碟管理
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES e2fsprogs fdisk smartmontools luci-app-diskman"

# Samba 4 局域網檔案共享
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES samba4-server luci-app-samba4"

# 常用命令列工具箱
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES wget-ssl htop lsblk iperf3"

export CUSTOM_PACKAGES
