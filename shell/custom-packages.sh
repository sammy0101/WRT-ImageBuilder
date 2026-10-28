#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (預載繁體中文與 Argon 美化，一功能一行)
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設一同安裝)
# ==============================================================================
# 核心 Web 網頁介面 + 官方繁體中文語言包
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci luci-i18n-base-zh-tw luci-i18n-firewall-zh-tw"

# Argon 現代自適應主題
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# 旁路由通用底層相依套件 (預先植入)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tun ca-bundle curl tar coreutils-nohup bash"

# ==============================================================================
# 1. daeuniverse 官方最新代理 (支援 OpenWrt 25.12+ 與 ImmortalWrt)
# ==============================================================================
# honk (官方最新 Rust eBPF 核心 + LuCI 面板)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES honk luci-app-honk"

# dae (官方經典 eBPF 核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES dae luci-app-dae"

# ==============================================================================
# 2. 其他主流代理客戶端 (整套一行)
# ==============================================================================
# OpenClash (Clash.Meta / Mihomo 內核代理客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# PassWall (經典代理工具 + 常用組件)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# HomeProxy (ImmortalWrt 官方主推 sing-box 代理)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# Mihomo (輕量化 Clash.Meta 原生 LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# ShadowSocksR Plus+ (SSR-Plus 老牌代理工具)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus"

# v2rayA (Xray/V2Ray 核心 + Web 介面)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES v2raya xray-core luci-app-v2raya"

# ==============================================================================
# 3. DNS 防污染與廣告過濾 (整套一行)
# ==============================================================================
# SmartDNS (防污染 DNS 核心 + LuCI 管理面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES smartdns luci-app-smartdns"

# MosDNS (模組化 DNS 分流核心 + LuCI 管理面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns"

# AdGuard Home (廣告攔截核心 + LuCI 管理面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adguardhome luci-app-adguardhome"

# Adblock (官方輕量廣告攔截核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES adblock luci-app-adblock"

# ==============================================================================
# 4. 異地組網、內網穿透與 VPN (整套一行)
# ==============================================================================
# Tailscale (WireGuard 異地互聯核心 + 防火牆規則 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft luci-app-tailscale"

# ZeroTier (虛擬區域網路 P2P 穿透核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES zerotier luci-app-zerotier"

# WireGuard (高效能 VPN 核心驅動 + 工具鏈 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-wireguard wireguard-tools luci-app-wireguard"

# FRP Client (內網穿透客戶端核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES frpc luci-app-frpc"

# ==============================================================================
# 5. 常用網路功能、喚醒與動態域名 (整套一行)
# ==============================================================================
# UPnP 自動通訊埠對應 (服務核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES miniupnpd luci-app-upnp"

# WOL 網路喚醒 (喚醒工具 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES etherwake luci-app-wol"

# DDNS 動態域名解析 (腳本核心 + 泛用協定 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES ddns-scripts ddns-scripts-services luci-app-ddns"

# Socat 通訊埠轉發工具 (雙向轉發核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES socat luci-app-socat"

# MWAN3 多 WAN 負載均衡 (多撥/多線核心 + 規則工具 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES mwan3 luci-app-mwan3"

# SQM 流量控制 (抗 Bufferbloat 高延遲核心腳本 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES sqm-scripts luci-app-sqm"

# ==============================================================================
# 6. 系統監控、頻寬統計與維護 (整套一行)
# ==============================================================================
# ttyd (網頁終端機核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES ttyd luci-app-ttyd"

# 定時自動重啟 (維護排程面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# NLBWMon 流量統計 (監控守護進程 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES nlbwmon luci-app-nlbwmon"

# Statistics (collectd 統計守護核心 + 常用圖表外掛 + LuCI 圖表介面)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES collectd collectd-mod-cpu collectd-mod-interface collectd-mod-load luci-app-statistics"

# ==============================================================================
# 7. 磁碟管理、NAS 檔案共用與下載 (整套一行)
# ==============================================================================
# Diskman (磁碟分區管理 + 檔案系統工具 e2fsprogs/fdisk + SMART 健康檢測 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES e2fsprogs fdisk smartmontools luci-app-diskman"

# Samba 4 (Windows 局域網檔案共享服務端 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES samba4-server luci-app-samba4"

# 硬碟定時休眠 (休眠守護進程 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES hd-idle luci-app-hd-idle"

# Aria2 (高速下載核心 + WebRPC 介面 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES aria2 ariang luci-app-aria2"

# Transmission (經典 BT / PT 下載核心 + Web 介面 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES transmission-daemon-openssl transmission-web luci-app-transmission"

# qBittorrent (功能強大的 BitTorrent 下載核心 + LuCI 面板)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES qbittorrent luci-app-qbittorrent"

# ==============================================================================
# 8. 常用命令列排錯與測速工具 (整套一行)
# ==============================================================================
# 實用命令列工具箱 (完整版 wget + curl + htop 監控 + 磁碟工具 + 局域網測速 iperf3)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget-ssl htop lsblk fdisk e2fsprogs iperf3"

export CUSTOM_PACKAGES
