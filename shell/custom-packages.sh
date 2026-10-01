#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (極簡原生英文版，分類齊全)
#
# 【使用說明】:
# 預設僅啟用 LuCI Web 介面與 Argon 主題。
# 若需要安裝某個外掛，只需刪除該行最前面的「#」號解除註解即可。
# （Docker 請直接在 GitHub Actions 頁面勾選，此處無需設定）
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設啟用)
# ==============================================================================
# 核心 Web 網頁介面 (原生英文)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# Argon 現代自適應主題 (若想用官方原生 Bootstrap 主題，可在該行開頭加 #)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# ==============================================================================
# 1. 代理客戶端與科學上網 (Proxy Clients)
# ==============================================================================
# OpenClash (基於 Clash.Meta / Mihomo 內核的進階代理工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# PassWall (經典穩定的代理工具，支援 Trojan/VLESS/Hysteria2/TUIC/SS)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# HomeProxy (ImmortalWrt 官方主推，基於 sing-box 的高效能透明代理)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# Mihomo (新一代輕量化 Clash.Meta 原生 LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# ShadowSocksR Plus+ (SSR-Plus 老牌代理工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus"

# v2rayA (基於 Xray/V2Ray 核心的多協議網頁版客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-v2raya"

# ==============================================================================
# 2. DNS 防污染、解析加速與廣告過濾 (DNS & AdBlock)
# ==============================================================================
# SmartDNS (本機防污染 DNS 伺服器，支援測速、分流與快取優化)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-smartdns"

# MosDNS (現代化模組化 DNS 分流工具，常與各類代理搭配)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns"

# AdGuard Home (全網絡廣告與隱私追蹤攔截 DNS 伺服器)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-adguardhome"

# Adblock (官方輕量原生廣告過濾外掛)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-adblock"

# ==============================================================================
# 3. 異地組網、內網穿透與虛擬私有網路 (VPN & Network Tunnel)
# ==============================================================================
# Tailscale (跨平台 WireGuard 零設定異地互聯)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-tailscale"

# ZeroTier (虛擬區域網路 P2P 穿透互聯)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-zerotier"

# WireGuard (現代輕量高效能 VPN 通道)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wireguard"

# FRP Client (內網穿透客戶端，將內網服務映射至公網伺服器)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-frpc"

# ==============================================================================
# 4. 常用網路功能、喚醒與動態域名 (Network Utilities)
# ==============================================================================
# UPnP 自動通訊埠對應 (BT/PT 下載與遊戲聯網必備)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp"

# WOL 網路喚醒 (遠端喚醒區域網路內的電腦/NAS/伺服器)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol"

# DDNS 動態域名解析 (搭配 Cloudflare/Aliyun 解析浮動公網 IP)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ddns"

# Socat 通訊埠轉發工具 (支援 IPv4/IPv6 雙向轉發)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-socat"

# MWAN3 (多 WAN 線路接入、多撥與負載均衡)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mwan3"

# SQM 流量控制 (智慧隊列管理，徹底解決 Bufferbloat 高延遲問題)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-sqm"

# ==============================================================================
# 5. 系統監控、頻寬統計與自動維護 (System & Monitoring)
# ==============================================================================
# ttyd (直接在網頁後台開啟 Linux 終端機)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd"

# 定時自動重啟 (維持設備長時間穩定運行)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# NLBWMon 流量統計 (即時與歷史監控各聯網設備的頻寬消耗)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-nlbwmon"

# Statistics (基於 collectd 的圖表監控，可看 CPU 溫度、負載、即時流量曲線)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-statistics"

# ==============================================================================
# 6. 磁碟管理、NAS 檔案共用與下載 (Storage, NAS & Downloads)
# ==============================================================================
# Diskman (磁碟分區、格式化與硬碟健康度 SMART 掛載管理)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman"

# Samba 4 (Windows 網路芳鄰/局域網高速檔案共用)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4"

# 硬碟定時休眠 (保護外接 USB/SATA 機械硬碟壽命與節能)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-hd-idle"

# Aria2 (輕量化高效能離線下載工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-aria2"

# Transmission (經典 BT / PT 下載工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-transmission"

# qBittorrent (功能強大的 BitTorrent / PT 下載客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-qbittorrent"

# ==============================================================================
# 7. 常用命令列排錯與測速工具 (CLI Utilities & Diagnostics)
# ==============================================================================
# 常用硬體與系統工具 (curl, wget, htop, 磁碟工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget-ssl htop lsblk fdisk e2fsprogs"

# 網路測速工具 (iperf3 局域網測速)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES iperf3"

export CUSTOM_PACKAGES
