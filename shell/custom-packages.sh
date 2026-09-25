#!/usr/bin/env bash
# ==============================================================================
# 自訂擴充軟體包選單 (相容 OpenWrt / ImmortalWrt 23.05 / 24.10 / 25.12+)
#
# 【使用說明】:
# 預設僅保留極簡純淨 Web 介面。
# 若需要安裝某個外掛，只需刪除該行最前面的「#」號解除註解即可。
# ==============================================================================

CUSTOM_PACKAGES=""

# ==============================================================================
# 0. 核心基礎套件 (預設啟用，確保擁有繁體中文 Web 後台)
# ==============================================================================
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-tw"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-tw"

# ==============================================================================
# 1. 代理 / 翻牆 / 旁路由客戶端 (按需解鎖)
# 【注意】ImmortalWrt 官方庫完整收錄以下插件；OpenWrt 官方原版部分外掛需自備依賴
# ==============================================================================
# --- OpenClash (基於 Clash Meta 內核的進階代理客戶端) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# --- PassWall 2 (經典穩定的代理工具，支援 Trojan/VLESS/Hysteria 等) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

# --- Mihomo / Clash.Meta 輕量客戶端 ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mihomo"

# --- ShadowSocksR Plus+ (SSR-Plus) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus"

# --- v2rayA (網頁版多協議代理客戶端) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-v2raya"

# ==============================================================================
# 2. DNS 防污染與解析加速
# ==============================================================================
# --- SmartDNS (本機高效防污染 DNS 伺服器，支援分流與最佳測速) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-smartdns luci-i18n-smartdns-zh-tw"

# --- MosDNS (現代化模組化 DNS 分流工具) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns"

# ==============================================================================
# 3. 異地組網、穿透與虛擬私有網路 (VPN)
# ==============================================================================
# --- Tailscale (跨平台 WireGuard 零設定異地互聯) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale iptables-nft"

# --- ZeroTier (虛擬局域網穿透互聯) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-zerotier luci-i18n-zerotier-zh-tw"

# --- WireGuard (現代輕量高效能 VPN 通道) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wireguard luci-i18n-wireguard-zh-tw"

# ==============================================================================
# 4. 系統美化、終端機與自動維護
# ==============================================================================
# --- Argon 現代雙色自適應主題 ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# --- ttyd (免安裝軟體，直接在網頁後台開啟終端機) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-tw"

# --- 定時自動重啟 (維持長時間運行穩定) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-autoreboot"

# ==============================================================================
# 5. 網路優化、喚醒與動態域名
# ==============================================================================
# --- TurboACC 網路加速 (支援 FastPath 快捷轉發、BBR 擁塞控制，僅限 ImmortalWrt) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc"

# --- UPnP 自動通訊埠對應 (BT/PT 下載與遊戲聯網必備) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-upnp luci-i18n-upnp-zh-tw"

# --- WOL 網路喚醒 (遠端喚醒區域網路內的電腦/NAS) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-wol luci-i18n-wol-zh-tw"

# --- DDNS 動態域名解析 (搭配 Cloudflare/Aliyun 解析浮動公網 IP) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ddns luci-i18n-ddns-zh-tw"

# --- 流量統計 (監控各設備即時與歷史流量) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-nlbwmon luci-i18n-nlbwmon-zh-tw"

# --- Socat 通訊埠轉發工具 ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-socat luci-i18n-socat-zh-tw"

# ==============================================================================
# 6. 磁碟管理、檔案共用與硬碟休眠 (軟路由 / NAS 用戶推薦)
# ==============================================================================
# --- Diskman (磁碟分區、格式化與掛載管理) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-diskman luci-i18n-diskman-zh-tw"

# --- Samba 4 (Windows 網路芳鄰/局域網共享檔案) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-samba4 luci-i18n-samba4-zh-tw"

# --- 硬碟定時休眠 (保護外接 USB/SATA 機械硬碟壽命) ---
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-hd-idle luci-i18n-hd-idle-zh-tw"

# ==============================================================================
# 7. 常用命令列工具 (建議開發與調試時按需啟用)
# ==============================================================================
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget htop lsblk fdisk e2fsprogs"

export CUSTOM_PACKAGES
