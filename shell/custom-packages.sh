#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (相容 OpenWrt / ImmortalWrt 23.05 / 24.10 / 25.12+)
#
# 【標籤圖示說明】:
#  🟢 [雙系統 100% 通用]   : OpenWrt 原版與 ImmortalWrt 官方源均內建，直接可用
#  🟡 [代理外掛 - 擴充解鎖] : ImmortalWrt 內建；OpenWrt 需透過 build.sh 自動注入擴充源
#  🔴 [ImmortalWrt 獨佔]   : 需依賴特定內核補丁，原版 OpenWrt 無法使用
#
# 【使用方法】: 想安裝哪個外掛，將該行最前面的「#」刪除即可。
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設啟用，確保具備繁體中文 Web 後台)
# ==============================================================================
# 🟢 [雙系統通用]
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-tw"

# ==============================================================================
# 1. 代理 / 科學上網客戶端
# ==============================================================================
# 🟡 [代理外掛] HomeProxy (基於 sing-box 的高效能透明代理客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-homeproxy"

# 🟡 [代理外掛] DAED (基於 Linux eBPF 技術的高效透明代理，自帶獨立 Web 面板 端口:2023)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed"

# 🟡 [代理外掛] DAE (基於 eBPF 的輕量版透明代理核心與 LuCI 介面)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-dae"

# 🟡 [代理外掛] OpenClash (功能最強大的代理工具，內建 Clash.Meta / Mihomo 內核與分流規則)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# 🟡 [代理外掛] Mihomo (新一代輕量化 Clash.Meta 核心原生 LuCI 介面)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# 🟡 [代理外掛] PassWall (經典穩定的代理工具，支援 Trojan/VLESS/Hysteria2/TUIC/Shadowsocks)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# 🟡 [代理外掛] NekoBox (基於 sing-box 內核的通用代理客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-nekobox"

# 🟡 [代理外掛] ShadowSocksR Plus+ (SSR-Plus，經典老牌代理外掛)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus"

# 🟡 [代理外掛] v2rayA (基於 Xray/V2Ray 核心的多協議網頁版客戶端)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-v2raya"

# ==============================================================================
# 2. DNS 防污染、解析加速與廣告過濾
# ==============================================================================
# 🟡 [代理外掛] SmartDNS (本機防污染 DNS 伺服器，支援測速、分流與快取優化)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-smartdns luci-i18n-smartdns-zh-tw"

# 🟡 [代理外掛] MosDNS (現代化模組化 DNS 分流工具，常與各類代理搭配使用)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns"

# 🟡 [代理外掛] AdGuard Home (全網絡廣告與追蹤攔截 DNS 伺服器)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-adguardhome"

# ==============================================================================
# 3. 異地組網、內網穿透與 VPN
# ==============================================================================
# 🟢 [雙系統通用] Tailscale (跨平台 WireGuard 零設定異地互聯)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-tailscale"

# 🟢 [雙系統通用] ZeroTier (虛擬局域網 P2P 穿透互聯)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-zerotier luci-i18n-zerotier-zh-tw"

# 🟢 [雙系統通用] WireGuard (現代輕量高效能 VPN 通道)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wireguard luci-i18n-wireguard-zh-tw"

# ==============================================================================
# 4. 系統美化、終端機與自動維護
# ==============================================================================
# 🟢 [雙系統通用] Argon 現代自適應雙色主題
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# 🟢 [雙系統通用] ttyd (免安裝第三方軟體，直接在網頁後台開啟 Linux 終端機)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-tw"

# 🟢 [雙系統通用] 定時自動重啟 (維持長時間運行穩定)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# ==============================================================================
# 5. 網路優化、喚醒與動態域名
# ==============================================================================
# 🔴 [ImmortalWrt 獨佔] TurboACC 網路加速 (支援 FastPath 快捷轉發、BBR 擁塞控制，原版 OpenWrt 不支援)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc"

# 🟢 [雙系統通用] UPnP 自動通訊埠對應 (BT/PT 下載與連線遊戲必備)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp luci-i18n-upnp-zh-tw"

# 🟢 [雙系統通用] WOL 網路喚醒 (遠端喚醒區域網路內的電腦/NAS)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol luci-i18n-wol-zh-tw"

# 🟢 [雙系統通用] DDNS 動態域名解析 (搭配 Cloudflare/Aliyun 解析浮動公網 IP)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ddns luci-i18n-ddns-zh-tw"

# 🟢 [雙系統通用] 流量統計 (監控各設備即時與歷史流量)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-nlbwmon luci-i18n-nlbwmon-zh-tw"

# 🟢 [雙系統通用] Socat 通訊埠轉發工具
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-socat luci-i18n-socat-zh-tw"

# ==============================================================================
# 6. 磁碟管理、檔案共用與硬碟休眠 (軟路由 / NAS 用戶推薦)
# ==============================================================================
# 🟢 [雙系統通用] Diskman (磁碟分區、格式化與硬碟健康度掛載管理)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman luci-i18n-diskman-zh-tw"

# 🟢 [雙系統通用] Samba 4 (Windows 網路芳鄰/局域網共享檔案)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4 luci-i18n-samba4-zh-tw"

# 🟢 [雙系統通用] 硬碟定時休眠 (保護外接 USB/SATA 機械硬碟壽命)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-hd-idle luci-i18n-hd-idle-zh-tw"

# ==============================================================================
# 7. 常用命令列工具
# ==============================================================================
# 🟢 [雙系統通用]
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget htop lsblk fdisk e2fsprogs"

export CUSTOM_PACKAGES
