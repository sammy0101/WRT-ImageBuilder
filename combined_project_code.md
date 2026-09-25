# Complete Project Codebase
Generated on: Fri Sep 25 16:06:39 UTC 2026

## File: files/etc/uci-defaults/99-custom.sh
````sh
#!/bin/sh
# ==============================================================================
# 首航初始化腳本：開機首次啟動自動執行一次後自我銷毀
# ==============================================================================

LOG_FILE="/tmp/uci-defaults-init.log"
echo "=== 開始執行首航配置 $(date) ===" > "$LOG_FILE"

# 1. 強制設定預設語言為繁體中文 (台灣)
uci set luci.main.lang='zh_tw'
uci commit luci

# 2. 讀取自訂 LAN IP 設定
if [ -f "/etc/custom_lan_ip" ]; then
    . /etc/custom_lan_ip
fi
TARGET_LAN_IP="${CUSTOM_LAN_IP:-192.168.100.1}"

# 3. 網卡自動偵測邏輯 (單網口自動 DHCP 模式；多網口 eth0=WAN, 其餘網口=LAN)
ETH_COUNT=0
ETH_LIST=""

for eth in /sys/class/net/*; do
    ETH_NAME=$(basename "$eth")
    if [ "$ETH_NAME" != "lo" ] && [ -d "$eth/device" ]; then
        ETH_COUNT=$((ETH_COUNT + 1))
        ETH_LIST="$ETH_LIST $ETH_NAME"
    fi
done

echo "偵測到的物理網卡數量: $ETH_COUNT (網卡列表: $ETH_LIST)" >> "$LOG_FILE"

if [ "$ETH_COUNT" -le 1 ]; then
    # 單網口設備 (NAS 虛擬機或旁路由): 設為 DHCP 自動獲取 IP，避免網段衝突
    echo "配置單網口模式: 自動透過上級 DHCP 獲取 IP" >> "$LOG_FILE"
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr 2>/dev/null
    uci delete network.lan.netmask 2>/dev/null
else
    # 多網口設備: eth0 做為 WAN 接口，其餘做為 LAN 接口
    echo "配置多網口模式: 設定 LAN IP 為 $TARGET_LAN_IP" >> "$LOG_FILE"
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
fi

# 4. PPPoE 撥號配置
PPPOE_CONF="/etc/config/pppoe-settings"
if [ -f "$PPPOE_CONF" ]; then
    . "$PPPOE_CONF"
    if [ "$ENABLE_PPPOE" = "yes" ] && [ -n "$PPPOE_ACCOUNT" ]; then
        echo "套用 PPPoE 撥號帳號與密碼..." >> "$LOG_FILE"
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$PPPOE_ACCOUNT"
        uci set network.wan.password="$PPPOE_PASSWORD"
    fi
fi

# 5. 防火牆安全調試設定：預設允許 WAN 入站訪問以利首航連線 (除錯完成後建議關閉)
uci set firewall.@zone[1].input='ACCEPT'

uci commit network
uci commit firewall

echo "=== 首航配置完成 ===" >> "$LOG_FILE"
exit 0

````

## File: shell/sync-devices.py
````py
#!/usr/bin/env python3
"""
同步官方最新設備資料庫並自動注入中文化與設備註解，改寫 build-firmware.yml 選單
"""
import json
import re
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DEVICES_JSON_PATH = BASE_DIR / "data" / "devices.json"
WORKFLOW_PATH = BASE_DIR / ".github" / "workflows" / "build-firmware.yml"

# 1. 品牌英文 -> 繁體中文對照字典
VENDOR_ZH_MAP = {
    "x86": "x86",
    "FriendlyElec": "友善 NanoPi",
    "FriendlyARM": "友善 NanoPi",
    "Raspberry Pi": "樹莓派",
    "Xiaomi": "小米",
    "Redmi": "紅米",
    "GL.iNet": "GL.iNet",
    "ASUS": "華碩 ASUS",
    "TP-Link": "TP-Link",
    "Qihoo": "360",
    "360": "360",
    "JCG": "捷稀 JCG",
    "Phicomm": "斐訊",
    "H3C": "華三 H3C",
    "Bananapi": "香蕉派 Banana Pi",
    "Sinovoip": "香蕉派 Banana Pi",
    "Linksys": "領勢 Linksys",
    "Netgear": "網件 Netgear",
    "Mercusys": "水星",
    "ZTE": "中興 ZTE",
}

# 2. 熱門知名設備之精準中文詳細備註
KNOWN_DESCRIPTIONS = {
    "x86_generic": "[x86] 標準軟路由 / 工控機 (N100, J4125) / 虛擬機 (PVE, ESXi, PC)",
    "x86_legacy": "[x86] 傳統 BIOS 引導舊主機 (Legacy MBR)",
    "friendlyarm_nanopi-r2s": "[友善] NanoPi R2S (雙千兆經典軟路由)",
    "friendlyarm_nanopi-r2c": "[友善] NanoPi R2C (雙千兆軟路由)",
    "friendlyarm_nanopi-r4s": "[友善] NanoPi R4S (RK3399 高效軟路由)",
    "friendlyarm_nanopi-r4se": "[友善] NanoPi R4SE (內建 eMMC 高效軟路由)",
    "friendlyarm_nanopi-r5s": "[友善] NanoPi R5S (三網口 雙 2.5G 軟路由)",
    "friendlyarm_nanopi-r5c": "[友善] NanoPi R5C (雙 2.5G 迷你軟路由)",
    "friendlyarm_nanopi-r6s": "[友善] NanoPi R6S (RK3588 雙 2.5G 旗艦軟路由)",
    "friendlyarm_nanopi-r6c": "[友善] NanoPi R6C (RK3588 旗艦軟路由)",
    "rpi-4": "[樹莓派] Raspberry Pi 4 Model B / CM4",
    "rpi-5": "[樹莓派] Raspberry Pi 5 (新一代高效單板電腦)",
    "rpi-3": "[樹莓派] Raspberry Pi 3 Model B / B+",
    "xiaomi_redmi-router-ax6000": "[紅米] Redmi AX6000 (MT7986 旗艦家用路由)",
    "xiaomi_mi-router-ax3000t": "[小米] 小米路由器 AX3000T (高 CP 值 Wi-Fi 6)",
    "xiaomi_mi-router-wr30u": "[小米] 小米路由器 WR30U (一般版 / 電信運營商版)",
    "xiaomi_redmi-router-ax3200": "[紅米] Redmi AX3200 / 小米 AX6S",
    "xiaomi_mi-router-4a-gigabit": "[小米] 小米路由器 4A 千兆版 (MT7621)",
    "glinet_gl-mt3000": "[GL.iNet] GL-MT3000 (Beryl AX 便攜旅行路由)",
    "glinet_gl-mt6000": "[GL.iNet] GL-MT6000 (Flint 2 雙 2.5G 旗艦路由)",
    "glinet_gl-mt2500": "[GL.iNet] GL-MT2500 / MT2500A (Brume 2 雙網口網關)",
    "glinet_gl-axt1800": "[GL.iNet] GL-AXT1800 (Slate AX 三頻旅行路由)",
    "glinet_gl-ax1800": "[GL.iNet] GL-AX1800 (Flint 雙頻 Wi-Fi 6 路由)",
    "asus_tuf-gaming-ax4200": "[華碩] ASUS TUF Gaming AX4200 電競路由器",
    "tplink_tl-xdr6088": "[TP-Link] TL-XDR6088 (雙 2.5G 旗艦 Wi-Fi 6)",
    "qihoo_360-t7": "[360] 360 T7 (聯發科高性價比神機)",
    "jcg_q30-pro": "[捷稀] JCG Q30 Pro (MT7981 Wi-Fi 6)",
    "phicomm_k2p": "[斐訊] Phicomm K2P (MT7621 經典千兆神機)",
}

def format_chinese_name(pid, vendor, title, target):
    """將設備名稱與品牌轉換為優雅的中文描述格式"""
    # 1. 優先使用手動精心設定的中文解釋
    if pid in KNOWN_DESCRIPTIONS:
        return KNOWN_DESCRIPTIONS[pid]

    # 2. 自動中文化品牌名稱
    vendor_zh = VENDOR_ZH_MAP.get(vendor, vendor)
    
    # 清理標題重複包含品牌名稱的問題 (例: Xiaomi Xiaomi Router -> 路由器)
    clean_title = title
    for v in [vendor, vendor_zh]:
        clean_title = re.sub(rf"^{v}\s+", "", clean_title, flags=re.IGNORECASE)

    return f"[{vendor_zh}] {clean_title} ({target})"

def load_local_devices():
    if DEVICES_JSON_PATH.exists():
        with open(DEVICES_JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def fetch_upstream_devices():
    urls = [
        "https://downloads.immortalwrt.org/releases/24.10.0/.overview.json",
        "https://downloads.openwrt.org/releases/24.10.0/.overview.json"
    ]
    found_profiles = {}
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                for item in data.get("profiles", []):
                    pid = item.get("id")
                    target = item.get("target")
                    titles = item.get("titles", [])
                    title_str = titles[0].get("title", pid) if titles else pid
                    vendor_str = titles[0].get("vendor", "") if titles else ""
                    if pid and target:
                        found_profiles[pid] = {
                            "vendor": vendor_str,
                            "title": title_str,
                            "target": target
                        }
        except Exception as e:
            print(f"嘗試抓取 {url} 略過: {e}")
    return found_profiles

def main():
    print("正在讀取本地設備庫...")
    devices = load_local_devices()

    upstream = fetch_upstream_devices()
    print(f"掃描官方資料庫完畢，發現 {len(upstream)} 款設備規格。")

    # 自動中文化並收錄熱門品牌
    for pid, info in upstream.items():
        vendor_lower = info["vendor"].lower()
        if any(brand in vendor_lower for brand in ["xiaomi", "redmi", "gl.inet", "friendlyarm", "raspberry", "asus", "tplink", "qihoo"]):
            slug = pid.replace("-", "_").lower()
            name_zh = format_chinese_name(pid, info["vendor"], info["title"], info["target"])
            devices[slug] = {
                "name": name_zh,
                "target": info["target"],
                "profile": pid
            }

    # 確保基本 x86 條目始終存在
    if "x86_generic" not in devices:
        devices["x86_generic"] = {
            "name": KNOWN_DESCRIPTIONS["x86_generic"],
            "target": "x86/64",
            "profile": "generic"
        }
    if "x86_legacy" not in devices:
        devices["x86_legacy"] = {
            "name": KNOWN_DESCRIPTIONS["x86_legacy"],
            "target": "x86/64",
            "profile": "legacy"
        }

    # 寫入 data/devices.json
    DEVICES_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DEVICES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(devices, f, ensure_ascii=False, indent=2)
    print("✓ data/devices.json 已完成全設備中文標註與更新。")

    # 自動改寫 build-firmware.yml 下拉選單
    if WORKFLOW_PATH.exists():
        yaml_options = []
        for key, data in devices.items():
            yaml_options.append(f"          - '{key}: {data['name']}'")
        options_str = "\n".join(yaml_options)

        with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        pattern = r"(# --- AUTO_DEVICES_START ---)(.*?)(# --- AUTO_DEVICES_END ---)"
        replacement = f"\\1\n{options_str}\n          \\3"
        new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

        with open(WORKFLOW_PATH, "w", encoding="utf-8") as f:
            f.write(new_content)

        print("✓ build-firmware.yml 下拉選單已注入中文註解選項！")

if __name__ == "__main__":
    main()

````

## File: shell/custom-packages.sh
````sh
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

````

## File: shell/fetch-versions.sh
````sh
#!/usr/bin/env bash
# ==============================================================================
# 腳本名稱: fetch-versions.sh
# 功能描述: 自動讀取官方 OpenWrt 或 ImmortalWrt 的版本清單與最新正式發布版本
# ==============================================================================
set -euo pipefail

TARGET_TYPE="${1:-ImmortalWrt}"
ACTION="${2:-list}" # 支援 list 或 latest

case "${TARGET_TYPE,,}" in
  openwrt)
    REPO_URL="https://github.com/openwrt/openwrt.git"
    ;;
  immortalwrt)
    REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
    ;;
  *)
    echo "錯誤: 未知的韌體類型 '$TARGET_TYPE'，請指定 openwrt 或 immortalwrt。" >&2
    exit 1
    ;;
esac

# 透過 git ls-remote 即時查詢遠端 tags，免除 GitHub API 訪問頻率限制
RAW_TAGS=$(git ls-remote --tags --refs "$REPO_URL" "v[0-9]*" 2>/dev/null \
  | awk -F'/' '{print $3}' \
  | sed 's/^v//' \
  | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
  | sort -V -r | uniq)

# 當網路異常時的安全降級預設版本列表
if [ -z "$RAW_TAGS" ]; then
  if [[ "${TARGET_TYPE,,}" == "openwrt" ]]; then
    RAW_TAGS=$(printf "24.10.0\n23.05.5\n23.05.4\n23.05.3\n23.05.2")
  else
    RAW_TAGS=$(printf "24.10.0\n23.05.4\n23.05.3\n23.05.2\n21.02.7")
  fi
fi

if [ "$ACTION" = "latest" ]; then
  echo "$RAW_TAGS" | head -n 1
else
  echo "$RAW_TAGS"
fi

````

## File: build.sh
````sh
#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 23.05(opkg) / 24.10(opkg) / 25.12+(apk)，支援自動轉換 VMware .vmdk
# ==============================================================================
set -euo pipefail

FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-25.12.2}"
SELECTED_DEVICE="${DEVICE_MODEL:-x86_generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
TARGET_IP="${LAN_IP:-192.168.100.1}"
PPPOE_EN="${ENABLE_PPPOE:-false}"

# 1. 取得設備唯一標識鍵
DEVICE_KEY=$(echo "$SELECTED_DEVICE" | cut -d':' -f1 | tr -d ' ')
DEVICES_FILE="$PWD/data/devices.json"

TARGET_INPUT=""
PROFILE_NAME=""

if [ -f "$DEVICES_FILE" ]; then
  TARGET_INPUT=$(jq -r --arg k "$DEVICE_KEY" '.[$k].target // empty' "$DEVICES_FILE")
  PROFILE_NAME=$(jq -r --arg k "$DEVICE_KEY" '.[$k].profile // empty' "$DEVICES_FILE")
fi

if [ -z "$TARGET_INPUT" ] || [ -z "$PROFILE_NAME" ]; then
  echo "警告: 在 devices.json 未能找到 '$DEVICE_KEY'，預設回退至 x86/64 generic"
  TARGET_INPUT="x86/64"
  PROFILE_NAME="generic"
fi

echo "=========================================================="
echo "  開始構建雲端自訂韌體"
echo "  系統類型: $FW_TYPE"
echo "  系統版本: $FW_VER"
echo "  所選設備鍵名: $DEVICE_KEY"
echo "  目標架構 (Target): $TARGET_INPUT"
echo "  設備代號 (Profile): $PROFILE_NAME"
echo "  設定容量: $SIZE_IN_GB GB"
echo "=========================================================="

# 2. 驗證分區大小並將 GB 換算為 MB
if ! [[ "$SIZE_IN_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "錯誤: 輸入的空間大小必須為數字！當前值: '$SIZE_IN_GB'" >&2
  exit 1
fi
PARTSIZE_MB=$(awk -v gb="$SIZE_IN_GB" 'BEGIN { printf "%.0f", gb * 1024 }')
echo "✓ 軟體包分區已轉換: ${SIZE_IN_GB} GB -> ${PARTSIZE_MB} MB"

# 3. 解析 Target 與 Subtarget
IFS='/' read -r TARGET_DIR SUBTARGET_DIR <<< "$TARGET_INPUT"

# 4. 下載官方 ImageBuilder
if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  BASE_URL="https://downloads.openwrt.org/releases/${FW_VER}/targets/${TARGET_DIR}/${SUBTARGET_DIR}"
  ARCHIVE_NAME="openwrt-imagebuilder-${FW_VER}-${TARGET_DIR}-${SUBTARGET_DIR}.Linux-x86_64.tar.zst"
else
  BASE_URL="https://downloads.immortalwrt.org/releases/${FW_VER}/targets/${TARGET_DIR}/${SUBTARGET_DIR}"
  ARCHIVE_NAME="immortalwrt-imagebuilder-${FW_VER}-${TARGET_DIR}-${SUBTARGET_DIR}.Linux-x86_64.tar.zst"
fi

WORKDIR="$PWD/build_workspace"
OUTPUT_DIR="$PWD/output"
mkdir -p "$WORKDIR" "$OUTPUT_DIR"

echo "下載官方 ImageBuilder: $BASE_URL/$ARCHIVE_NAME"
if ! wget -q -c "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"; then
  ARCHIVE_NAME="${ARCHIVE_NAME%.zst}.xz"
  echo "嘗試 .tar.xz 備用格式: $BASE_URL/$ARCHIVE_NAME"
  wget -c "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"
fi

echo "正在解壓縮 ImageBuilder..."
tar -xf "$WORKDIR/$ARCHIVE_NAME" -C "$WORKDIR"
EXTRACTED_DIR=$(find "$WORKDIR" -maxdepth 1 -type d -name "*imagebuilder*" | head -n 1)
cd "$EXTRACTED_DIR"

# 5. 整合 Overlay 檔案 (files 系統覆蓋層)
mkdir -p files/etc/uci-defaults files/etc/config
cp -r "$PWD/../../files/"* files/

echo "CUSTOM_LAN_IP=\"$TARGET_IP\"" > files/etc/custom_lan_ip

if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 整合軟體包清單與版本過濾
source "$PWD/../../shell/custom-packages.sh"
PACKAGES_TO_BUILD="$CUSTOM_PACKAGES"

if [[ "$DOCKER_FLAG" == "true" ]]; then
  echo "✓ 已勾選整合 Docker 與 Dockerman 管理套件"
  PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-tw"
fi

if [[ "$FW_VER" =~ ^25\. ]] || [ -f "staging_dir/host/bin/apk" ]; then
  echo "ℹ️ 檢測到當前為 25.12+ apk 世代，自動清洗 opkg 舊式依賴包..."
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-i18n-opkg-zh-tw//g; s/luci-app-opkg//g')
fi

PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | xargs)
echo "最終包含軟體包列表: $PACKAGES_TO_BUILD"

# 7. 帶有自動容錯自癒（Self-Healing）的打包程序
execute_make_image() {
  local current_pkgs="$1"
  local log_tmp="/tmp/imagebuilder_build.log"

  echo "開始編譯產生固件映像檔..."
  if make image \
    PROFILE="$PROFILE_NAME" \
    PACKAGES="$current_pkgs" \
    FILES="files" \
    ROOTFS_PARTSIZE="$PARTSIZE_MB" \
    BIN_DIR="$OUTPUT_DIR" 2>&1 | tee "$log_tmp"; then
    return 0
  fi

  local missing_apk=$(grep -E '^\s+[a-zA-Z0-9_\.\-]+ \(no such package\):' "$log_tmp" | awk '{print $1}' | tr '\n' ' ')
  local missing_opkg=$(grep -oE "Unknown package '[^']+'" "$log_tmp" | cut -d"'" -f2 | tr '\n' ' ')
  local missing_opkg2=$(grep -oE "Cannot install package [^.]+" "$log_tmp" | awk '{print $NF}' | tr '\n' ' ')

  local all_missing=$(echo "$missing_apk $missing_opkg $missing_opkg2" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || echo "")

  if [ -n "$all_missing" ]; then
    echo ""
    echo "=========================================================="
    echo "⚠️ 偵測到當前官方軟體源缺少以下軟體包:"
    echo "   $all_missing"
    echo "🔄 觸發自動自癒機制：剔除缺失套件並自動重新構建..."
    echo "=========================================================="

    local cleaned_pkgs="$current_pkgs"
    for pkg in $all_missing; do
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )$pkg( |\$)/ /g")
    done
    cleaned_pkgs=$(echo "$cleaned_pkgs" | xargs)

    echo "修正後的軟體包列表: $cleaned_pkgs"
    echo ""

    make image \
      PROFILE="$PROFILE_NAME" \
      PACKAGES="$cleaned_pkgs" \
      FILES="files" \
      ROOTFS_PARTSIZE="$PARTSIZE_MB" \
      BIN_DIR="$OUTPUT_DIR"
    return $?
  fi

  return 1
}

execute_make_image "$PACKAGES_TO_BUILD"

# 8. 自動轉換 VMware .vmdk 虛擬磁碟格式 (僅限包含 combined 映像的 x86 系列)
if ls "$OUTPUT_DIR"/*combined* 1> /dev/null 2>&1; then
  echo ""
  echo "=========================================================="
  echo "  正在將 x86 映像轉換為 VMware (.vmdk) 格式..."
  echo "=========================================================="
  for img_gz in "$OUTPUT_DIR"/*combined*.img.gz; do
    [ -f "$img_gz" ] || continue
    base_name=$(basename "$img_gz" .img.gz)
    raw_tmp="/tmp/${base_name}.img"
    vmdk_target="$OUTPUT_DIR/${base_name}.vmdk"

    echo "轉換中: $base_name.img.gz -> $base_name.vmdk"
    gzip -dc "$img_gz" > "$raw_tmp"
    qemu-img convert -f raw -O vmdk "$raw_tmp" "$vmdk_target"
    rm -f "$raw_tmp"
  done
  echo "✓ VMware .vmdk 虛擬磁碟轉換完成！"
fi

echo "✓ 產物目錄清單:"
ls -lh "$OUTPUT_DIR"

````

## File: .github/workflows/combine-code.yml
````yml
name: Generate All Codebase to MD

on:
  push:
    branches:
      - main
    paths-ignore:
      - 'combined_project_code.md' # 避免此檔案自身更新引發無限循環
  workflow_dispatch: # 支援在 GitHub 網頁上手動觸發執行

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Combine All Files into MD
        run: |
          OUT_FILE="combined_project_code.md"
          echo "# Complete Project Codebase" > "$OUT_FILE"
          echo "Generated on: $(date)" >> "$OUT_FILE"
          echo "" >> "$OUT_FILE"

          # 遍歷專案內的所有檔案，排除依賴、Git 歷史、打包產物及二進位檔案
          find . -type f \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" \
            -not -path "*/dist/*" \
            -not -name "package-lock.json" \
            -not -name "yarn.lock" \
            -not -name "pnpm-lock.yaml" \
            -not -name "$OUT_FILE" \
            -not -name "*.png" \
            -not -name "*.jpg" \
            -not -name "*.jpeg" \
            -not -name "*.gif" \
            -not -name "*.ico" \
            -not -name "*.woff*" \
            -not -name "*.ttf" | while read -r file; do
              
              # 取得相對路徑與副檔名
              rel_path="${file#./}"
              ext="${file##*.}"
              
              # 如果無副檔名，清除變數避免格式混亂
              if [ "$ext" = "$rel_path" ]; then
                ext=""
              fi
              
              # 寫入檔案標題
              echo "## File: $rel_path" >> "$OUT_FILE"
              # 使用四個反單引號（````）包裹，防止內部程式碼的三個反單引號造成排版衝突
              echo "\`\`\`\`$ext" >> "$OUT_FILE"
              cat "$file" >> "$OUT_FILE"
              echo "" >> "$OUT_FILE"
              echo "\`\`\`\`" >> "$OUT_FILE"
              echo "" >> "$OUT_FILE"
          done

      - name: Commit and Push changes
        run: |
          git config --local user.email "github-actions[bot]@users.noreply.github.com"
          git config --local user.name "github-actions[bot]"
          git add combined_project_code.md
          
          if git diff --staged --quiet; then
            echo "No changes in codebase."
          else
            git commit -m "docs: auto-generate complete codebase [skip ci]"
            git push origin main
          fi

````

## File: .github/workflows/build-firmware.yml
````yml
name: 構建 OpenWrt / ImmortalWrt 自訂韌體

on:
  workflow_dispatch:
    inputs:
      firmware_type:
        description: '選擇韌體系統分支'
        required: true
        type: choice
        default: 'ImmortalWrt'
        options:
          - 'ImmortalWrt'
          - 'OpenWrt'

      luci_version:
        description: '韌體版本 (輸入 auto 或 latest 自動抓取最新正式版)'
        required: true
        default: 'auto'
        type: string

      rootfs_size_g:
        description: '軟體包分區空間大小 (單位：GB，請直接輸入數字，例如 1 或 2)'
        required: true
        default: '1'
        type: string

      device_model:
        description: '請直接從下拉選單選擇你的設備型號'
        required: true
        type: choice
        default: 'x86_generic: [x86] 標準軟路由 / 工控機 (N100, J4125) / 虛擬機 (PVE, ESXi, PC)'
        options:
          # --- AUTO_DEVICES_START ---
          - 'x86_generic: [x86] 標準軟路由 / 工控機 (N100, J4125) / 虛擬機 (PVE, ESXi, PC)'
          - 'x86_legacy: [x86] 傳統 BIOS 引導舊主機 (Legacy MBR)'
          - 'nanopi_r2s: [NanoPi] 友善 NanoPi R2S'
          - 'nanopi_r2c: [NanoPi] 友善 NanoPi R2C'
          - 'nanopi_r4s: [NanoPi] 友善 NanoPi R4S'
          - 'nanopi_r4se: [NanoPi] 友善 NanoPi R4SE'
          - 'nanopi_r5s: [NanoPi] 友善 NanoPi R5S'
          - 'nanopi_r5c: [NanoPi] 友善 NanoPi R5C'
          - 'nanopi_r6s: [NanoPi] 友善 NanoPi R6S'
          - 'nanopi_r6c: [NanoPi] 友善 NanoPi R6C'
          - 'rpi_4: [樹莓派] Raspberry Pi 4 Model B / CM4'
          - 'rpi_5: [樹莓派] Raspberry Pi 5'
          - 'rpi_3: [樹莓派] Raspberry Pi 3 Model B / B+'
          - 'redmi_ax6000: [紅米] Redmi AX6000 (MT7986)'
          - 'xiaomi_ax3000t: [小米] 小米路由器 AX3000T'
          - 'xiaomi_wr30u: [小米] 小米路由器 WR30U'
          - 'redmi_ax3200: [紅米] Redmi AX3200 / 小米 AX6S'
          - 'xiaomi_4a_gigabit: [小米] 小米路由器 4A 千兆版 (Gigabit)'
          - 'glinet_mt3000: [GL.iNet] GL-MT3000 (Beryl AX)'
          - 'glinet_mt6000: [GL.iNet] GL-MT6000 (Flint 2)'
          - 'glinet_mt2500: [GL.iNet] GL-MT2500 / MT2500A (Brume 2)'
          - 'glinet_axt1800: [GL.iNet] GL-AXT1800 (Slate AX)'
          - 'glinet_ax1800: [GL.iNet] GL-AX1800 (Flint)'
          - 'asus_tuf_ax4200: [華碩] ASUS TUF Gaming AX4200'
          - 'tplink_xdr6088: [TP-Link] TL-XDR6088 雙 2.5G 路由器'
          - 'qihoo_360t7: [360] 360 T7 路由器'
          - 'jcg_q30pro: [捷稀] JCG Q30 Pro'
          - 'phicomm_k2p: [斐訊] Phicomm K2P (MT7621)'
          - 'asus_rt_ac3100: [ASUS] asus_rt-ac3100'
          - 'asus_rt_ac56u: [ASUS] asus_rt-ac56u'
          - 'asus_rt_ac68u: [ASUS] asus_rt-ac68u'
          - 'asus_rt_ac87u: [ASUS] asus_rt-ac87u'
          - 'asus_rt_ac88u: [ASUS] asus_rt-ac88u'
          - 'asus_rt_n18u: [ASUS] asus_rt-n18u'
          - 'xiaomi_redmi_router_ax6s: [Xiaomi] xiaomi_redmi-router-ax6s'
          - 'asus_rt_ax59u: [ASUS] asus_rt-ax59u'
          - 'asus_tuf_ax6000: [ASUS] asus_tuf-ax6000'
          - 'glinet_gl_mt2500: [GL.iNet] glinet_gl-mt2500'
          - 'glinet_gl_mt3000: [GL.iNet] glinet_gl-mt3000'
          - 'glinet_gl_mt6000: [GL.iNet] glinet_gl-mt6000'
          - 'glinet_gl_x3000: [GL.iNet] glinet_gl-x3000'
          - 'glinet_gl_xe3000: [GL.iNet] glinet_gl-xe3000'
          - 'xiaomi_mi_router_ax3000t: [Xiaomi] xiaomi_mi-router-ax3000t'
          - 'xiaomi_mi_router_ax3000t_ubootmod: [Xiaomi] xiaomi_mi-router-ax3000t-ubootmod'
          - 'xiaomi_mi_router_wr30u_stock: [Xiaomi] xiaomi_mi-router-wr30u-stock'
          - 'xiaomi_mi_router_wr30u_ubootmod: [Xiaomi] xiaomi_mi-router-wr30u-ubootmod'
          - 'xiaomi_redmi_router_ax6000_stock: [Xiaomi] xiaomi_redmi-router-ax6000-stock'
          - 'xiaomi_redmi_router_ax6000_ubootmod: [Xiaomi] xiaomi_redmi-router-ax6000-ubootmod'
          - 'asus_onhub: [ASUS] asus_onhub'
          - 'xiaomi_mi_router_hd: [Xiaomi] xiaomi_mi-router-hd'
          - 'rpi_2: [Raspberry Pi] rpi-2'
          - 'rpi: [Raspberry Pi] rpi'
          - 'friendlyarm_nanopc_t4: [FriendlyARM] friendlyarm_nanopc-t4'
          - 'friendlyarm_nanopc_t6: [FriendlyARM] friendlyarm_nanopc-t6'
          - 'friendlyarm_nanopi_r2c: [FriendlyARM] friendlyarm_nanopi-r2c'
          - 'friendlyarm_nanopi_r2c_plus: [FriendlyARM] friendlyarm_nanopi-r2c-plus'
          - 'friendlyarm_nanopi_r2s: [FriendlyARM] friendlyarm_nanopi-r2s'
          - 'friendlyarm_nanopi_r3s: [FriendlyARM] friendlyarm_nanopi-r3s'
          - 'friendlyarm_nanopi_r4s: [FriendlyARM] friendlyarm_nanopi-r4s'
          - 'friendlyarm_nanopi_r4s_enterprise: [FriendlyARM] friendlyarm_nanopi-r4s-enterprise'
          - 'friendlyarm_nanopi_r4se: [FriendlyARM] friendlyarm_nanopi-r4se'
          - 'friendlyarm_nanopi_r5c: [FriendlyARM] friendlyarm_nanopi-r5c'
          - 'friendlyarm_nanopi_r5s: [FriendlyARM] friendlyarm_nanopi-r5s'
          - 'friendlyarm_nanopi_r6c: [FriendlyARM] friendlyarm_nanopi-r6c'
          - 'friendlyarm_nanopi_r6s: [FriendlyARM] friendlyarm_nanopi-r6s'
          - 'glinet_gl_mv1000: [GL.iNet] glinet_gl-mv1000'
          - 'asus_rt_ax89x: [Asus] asus_rt-ax89x'
          - 'redmi_ax6: [Redmi] redmi_ax6'
          - 'redmi_ax6_stock: [Redmi] redmi_ax6-stock'
          - 'xiaomi_ax3600: [Xiaomi] xiaomi_ax3600'
          - 'xiaomi_ax3600_stock: [Xiaomi] xiaomi_ax3600-stock'
          - 'xiaomi_ax9000: [Xiaomi] xiaomi_ax9000'
          - 'asus_rp_n53: [ASUS] asus_rp-n53'
          - 'asus_rt_ac51u: [ASUS] asus_rt-ac51u'
          - 'asus_rt_ac54u: [ASUS] asus_rt-ac54u'
          - 'asus_rt_n14u: [ASUS] asus_rt-n14u'
          - 'glinet_gl_mt300a: [GL.iNet] glinet_gl-mt300a'
          - 'glinet_gl_mt300n: [GL.iNet] glinet_gl-mt300n'
          - 'glinet_gl_mt750: [GL.iNet] glinet_gl-mt750'
          - 'xiaomi_miwifi_mini: [Xiaomi] xiaomi_miwifi-mini'
          - 'asus_rt_ac1200: [ASUS] asus_rt-ac1200'
          - 'asus_rt_ac1200_v2: [ASUS] asus_rt-ac1200-v2'
          - 'asus_rt_n12_vp_b1: [ASUS] asus_rt-n12-vp-b1'
          - 'glinet_gl_mt300n_v2: [GL.iNet] glinet_gl-mt300n-v2'
          - 'glinet_microuter_n300: [GL.iNet] glinet_microuter-n300'
          - 'glinet_vixmini: [GL.iNet] glinet_vixmini'
          - 'xiaomi_mi_ra75: [Xiaomi] xiaomi_mi-ra75'
          - 'xiaomi_mi_router_4a_100m: [Xiaomi] xiaomi_mi-router-4a-100m'
          - 'xiaomi_mi_router_4a_100m_intl: [Xiaomi] xiaomi_mi-router-4a-100m-intl'
          - 'xiaomi_mi_router_4a_100m_intl_v2: [Xiaomi] xiaomi_mi-router-4a-100m-intl-v2'
          - 'xiaomi_mi_router_4c: [Xiaomi] xiaomi_mi-router-4c'
          - 'xiaomi_miwifi_3c: [Xiaomi] xiaomi_miwifi-3c'
          - 'xiaomi_miwifi_nano: [Xiaomi] xiaomi_miwifi-nano'
          - 'asus_rp_ac56: [ASUS] asus_rp-ac56'
          - 'asus_rp_ac87: [ASUS] asus_rp-ac87'
          - 'asus_rt_ac57u_v1: [ASUS] asus_rt-ac57u-v1'
          - 'asus_rt_ac65p: [ASUS] asus_rt-ac65p'
          - 'asus_rt_ac85p: [ASUS] asus_rt-ac85p'
          - 'asus_rt_ax53u: [ASUS] asus_rt-ax53u'
          - 'asus_rt_ax54: [ASUS] asus_rt-ax54'
          - 'asus_rt_n56u_b1: [ASUS] asus_rt-n56u-b1'
          - 'glinet_gl_mt1300: [GL.iNet] glinet_gl-mt1300'
          - 'xiaomi_mi_router_3_pro: [Xiaomi] xiaomi_mi-router-3-pro'
          - 'xiaomi_mi_router_3g: [Xiaomi] xiaomi_mi-router-3g'
          - 'xiaomi_mi_router_3g_v2: [Xiaomi] xiaomi_mi-router-3g-v2'
          - 'xiaomi_mi_router_4: [Xiaomi] xiaomi_mi-router-4'
          - 'xiaomi_mi_router_4a_gigabit: [Xiaomi] xiaomi_mi-router-4a-gigabit'
          - 'xiaomi_mi_router_4a_gigabit_v2: [Xiaomi] xiaomi_mi-router-4a-gigabit-v2'
          - 'xiaomi_mi_router_ac2100: [Xiaomi] xiaomi_mi-router-ac2100'
          - 'xiaomi_mi_router_cr6606: [Xiaomi] xiaomi_mi-router-cr6606'
          - 'xiaomi_mi_router_cr6608: [Xiaomi] xiaomi_mi-router-cr6608'
          - 'xiaomi_mi_router_cr6609: [Xiaomi] xiaomi_mi-router-cr6609'
          - 'xiaomi_redmi_router_ac2100: [Xiaomi] xiaomi_redmi-router-ac2100'
          - 'asus_map_ac2200: [ASUS] asus_map-ac2200'
          - 'asus_rt_ac42u: [ASUS] asus_rt-ac42u'
          - 'asus_rt_ac58u: [ASUS] asus_rt-ac58u'
          - 'glinet_gl_a1300: [GL.iNet] glinet_gl-a1300'
          - 'glinet_gl_ap1300: [GL.iNet] glinet_gl-ap1300'
          - 'glinet_gl_b1300: [GL.iNet] glinet_gl-b1300'
          - 'glinet_gl_b2200: [GL.iNet] glinet_gl-b2200'
          - 'friendlyarm_nanopi_neo_plus2: [FriendlyARM] friendlyarm_nanopi-neo-plus2'
          - 'friendlyarm_nanopi_neo2: [FriendlyARM] friendlyarm_nanopi-neo2'
          - 'friendlyarm_nanopi_r1s_h5: [FriendlyARM] friendlyarm_nanopi-r1s-h5'
          - 'friendlyarm_nanopi_m1_plus: [FriendlyARM] friendlyarm_nanopi-m1-plus'
          - 'friendlyarm_nanopi_neo: [FriendlyARM] friendlyarm_nanopi-neo'
          - 'friendlyarm_nanopi_neo_air: [FriendlyARM] friendlyarm_nanopi-neo-air'
          - 'friendlyarm_nanopi_r1: [FriendlyARM] friendlyarm_nanopi-r1'
          - 'friendlyarm_zeropi: [FriendlyARM] friendlyarm_zeropi'
          - 'glinet_gl_ar300m_nand: [GL.iNet] glinet_gl-ar300m-nand'
          - 'glinet_gl_ar300m_nor: [GL.iNet] glinet_gl-ar300m-nor'
          - 'glinet_gl_ar750s_nor: [GL.iNet] glinet_gl-ar750s-nor'
          - 'glinet_gl_ar750s_nor_nand: [GL.iNet] glinet_gl-ar750s-nor-nand'
          - 'glinet_gl_e750: [GL.iNet] glinet_gl-e750'
          - 'glinet_gl_s200_nor: [GL.iNet] glinet_gl-s200-nor'
          - 'glinet_gl_s200_nor_nand: [GL.iNet] glinet_gl-s200-nor-nand'
          - 'glinet_gl_x1200_nor: [GL.iNet] glinet_gl-x1200-nor'
          - 'glinet_gl_x1200_nor_nand: [GL.iNet] glinet_gl-x1200-nor-nand'
          - 'glinet_gl_xe300: [GL.iNet] glinet_gl-xe300'
          - 'asus_pl_ac56: [ASUS] asus_pl-ac56'
          - 'asus_rp_ac51: [ASUS] asus_rp-ac51'
          - 'asus_rp_ac66: [ASUS] asus_rp-ac66'
          - 'asus_rt_ac59u: [ASUS] asus_rt-ac59u'
          - 'asus_rt_ac59u_v2: [ASUS] asus_rt-ac59u-v2'
          - 'asus_zenwifi_cd6n: [ASUS] asus_zenwifi-cd6n'
          - 'asus_zenwifi_cd6r: [ASUS] asus_zenwifi-cd6r'
          - 'glinet_6408: [GL.iNet] glinet_6408'
          - 'glinet_6416: [GL.iNet] glinet_6416'
          - 'glinet_gl_ar150: [GL.iNet] glinet_gl-ar150'
          - 'glinet_gl_ar300m_lite: [GL.iNet] glinet_gl-ar300m-lite'
          - 'glinet_gl_ar300m16: [GL.iNet] glinet_gl-ar300m16'
          - 'glinet_gl_ar750: [GL.iNet] glinet_gl-ar750'
          - 'glinet_gl_mifi: [GL.iNET] glinet_gl-mifi'
          - 'glinet_gl_usb150: [GL.iNET] glinet_gl-usb150'
          - 'glinet_gl_x300b: [GL.iNet] glinet_gl-x300b'
          - 'glinet_gl_x750: [GL.iNet] glinet_gl-x750'
          - 'xiaomi_aiot_ac2350: [Xiaomi] xiaomi_aiot-ac2350'
          - 'xiaomi_mi_router_4q: [Xiaomi] xiaomi_mi-router-4q'
          - 'asus_rt_ac53u: [ASUS] asus_rt-ac53u'
          - 'asus_rt_n14uhp: [ASUS] asus_rt-n14uhp'
          - 'asus_rt_n15u: [ASUS] asus_rt-n15u'
          - 'asus_rt_n16: [ASUS] asus_rt-n16'
          - 'asus_rt_n66u: [ASUS] asus_rt-n66u'
          - 'asus_rt_n66w: [ASUS] asus_rt-n66w'
          - 'asus_gt_ac5300: [ASUS] asus_gt-ac5300'
          - 'asus_rt_n56u: [ASUS] asus_rt-n56u'
          # --- AUTO_DEVICES_END ---

      include_docker:
        description: '是否整合 Docker 與 Dockerman 容器介面'
        required: false
        type: boolean
        default: false

      lan_ip:
        description: '自訂管理 LAN 端 IP (多網口機型預設 192.168.100.1)'
        required: false
        default: '192.168.100.1'
        type: string

      enable_pppoe:
        description: '是否啟用 WAN 端 PPPoE 撥號'
        required: false
        type: boolean
        default: false

      pppoe_account:
        description: 'PPPoE 撥號帳號 (未啟用可留空)'
        required: false
        default: ''
        type: string

      pppoe_password:
        description: 'PPPoE 撥號密碼 (未啟用可留空)'
        required: false
        default: ''
        type: string

jobs:
  build:
    name: 構建韌體 (${{ inputs.firmware_type }})
    runs-on: ubuntu-24.04
    permissions:
      contents: write

    steps:
      - name: 檢出專案代碼
        uses: actions/checkout@v4

      - name: 安裝編譯相依套件 (含 ISO 與虛擬化轉換工具)
        run: |
          sudo apt-get update
          sudo apt-get install -y build-essential libncurses5-dev zlib1g-dev gawk git \
            gettext libssl-dev xsltproc wget unzip python3 zstd file jq curl qemu-utils \
            genisoimage dosfstools mtools xorriso
          
          if ! command -v mkisofs &>/dev/null && command -v genisoimage &>/dev/null; then
            sudo ln -s "$(which genisoimage)" /usr/local/bin/mkisofs
          fi

      - name: 解析與自動讀取韌體版本
        id: resolve_version
        run: |
          chmod +x shell/fetch-versions.sh
          INPUT_VER="${{ inputs.luci_version }}"
          FW_TYPE="${{ inputs.firmware_type }}"
          
          if [[ "$INPUT_VER" == "auto" || "$INPUT_VER" == "latest" || -z "$INPUT_VER" ]]; then
            echo "正在查詢 $FW_TYPE 最新正式發布版本..."
            DETECTED_VER=$(./shell/fetch-versions.sh "$FW_TYPE" latest)
            echo "✓ 選定最新版本: $DETECTED_VER"
            echo "version=$DETECTED_VER" >> $GITHUB_OUTPUT
          else
            echo "使用指定版本: $INPUT_VER"
            echo "version=$INPUT_VER" >> $GITHUB_OUTPUT
          fi

      - name: 執行韌體生成構建
        id: run_builder
        env:
          FIRMWARE_TYPE: ${{ inputs.firmware_type }}
          VERSION: ${{ steps.resolve_version.outputs.version }}
          DEVICE_MODEL: ${{ inputs.device_model }}
          ROOTFS_SIZE_G: ${{ inputs.rootfs_size_g }}
          INCLUDE_DOCKER: ${{ inputs.include_docker }}
          LAN_IP: ${{ inputs.lan_ip }}
          ENABLE_PPPOE: ${{ inputs.enable_pppoe }}
          PPPOE_ACCOUNT: ${{ inputs.pppoe_account }}
          PPPOE_PASSWORD: ${{ inputs.pppoe_password }}
        run: |
          chmod +x build.sh
          chmod +x shell/custom-packages.sh
          chmod +x files/etc/uci-defaults/99-custom.sh
          ./build.sh

      - name: 產生校驗碼與構建摘要
        id: summary
        run: |
          cd output
          sha256sum * > sha256sums.txt
          
          echo "### 構建成果摘要 🚀" >> $GITHUB_STEP_SUMMARY
          echo "- **系統分支**: ${{ inputs.firmware_type }}" >> $GITHUB_STEP_SUMMARY
          echo "- **固件版本**: ${{ steps.resolve_version.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **設備型號**: ${{ inputs.device_model }}" >> $GITHUB_STEP_SUMMARY
          echo "- **軟體包分區大小**: ${{ inputs.rootfs_size_g }} GB" >> $GITHUB_STEP_SUMMARY
          echo "- **管理網址**: http://${{ inputs.lan_ip }}" >> $GITHUB_STEP_SUMMARY
          echo "- **預設帳號**: \`root\`" >> $GITHUB_STEP_SUMMARY
          echo "- **預設密碼**: \`無密碼（直接留空登入）\`" >> $GITHUB_STEP_SUMMARY
          echo "#### 檔案 SHA256 校驗表" >> $GITHUB_STEP_SUMMARY
          echo '```text' >> $GITHUB_STEP_SUMMARY
          cat sha256sums.txt >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          
          echo "hashes<<EOF" >> $GITHUB_OUTPUT
          cat sha256sums.txt >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: 上傳韌體構建產物至 Artifacts (保留90天)
        uses: actions/upload-artifact@v4
        with:
          name: ${{ inputs.firmware_type }}-${{ steps.resolve_version.outputs.version }}-${{ inputs.rootfs_size_g }}G
          path: output/*

      # ==============================================================================
      # 自動正式發布至 GitHub Releases (永久保存)
      # ==============================================================================
      - name: 自動發布至 GitHub Releases
        uses: softprops/action-gh-release@v2
        if: ${{ success() }}
        with:
          tag_name: ${{ inputs.firmware_type }}-${{ steps.resolve_version.outputs.version }}-build${{ github.run_number }}
          name: ${{ inputs.firmware_type }} ${{ steps.resolve_version.outputs.version }} (${{ inputs.device_model }})
          body: |
            ### 🚀 韌體發布資訊
            - **韌體系統**: ${{ inputs.firmware_type }}
            - **系統版本**: ${{ steps.resolve_version.outputs.version }}
            - **硬體設備**: ${{ inputs.device_model }}
            - **磁碟空間**: ${{ inputs.rootfs_size_g }} GB
            - **虛擬化支援**: 包含原廠 `.img.gz`、VMware `.vmdk`、Hyper-V `.vhdx` 與安裝引導 `.iso`

            ### 🔑 預設登入認證資訊
            - **管理網址**: `http://${{ inputs.lan_ip }}`（單網卡設備請查詢上級 DHCP IP）
            - **使用者名稱 (User)**: `root`
            - **登入密碼 (Password)**: `無密碼（密碼欄留空，直接按登入即可）`

            #### 🔒 SHA256 檔案校驗碼
            ```text
            ${{ steps.summary.outputs.hashes }}
            ```
          files: output/*

````

## File: .github/workflows/sync-upstream.yml
````yml
name: 自動同步官方版本與支援設備

on:
  schedule:
    # 每週一 UTC 03:00 (台灣/香港時間 11:00) 自動檢查
    - cron: '0 3 * * 1'
  workflow_dispatch: # 支援在 GitHub 網頁上手動點擊一鍵更新

permissions:
  contents: write

jobs:
  sync-all:
    name: 同步最新版本與設備資料庫
    runs-on: ubuntu-latest

    steps:
      # 使用 SYNC_PAT 檢出專案，賦予寫入 .github/workflows 的權限
      - name: 檢出專案代碼
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.SYNC_PAT }}

      - name: 設定 Python 環境
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      # ----- 步驟 1：檢測 OpenWrt / ImmortalWrt 官方最新版本 -----
      - name: 查詢官方最新發行版本
        id: versions
        run: |
          chmod +x shell/fetch-versions.sh
          OPENWRT_LATEST=$(./shell/fetch-versions.sh openwrt latest)
          IMMORTALWRT_LATEST=$(./shell/fetch-versions.sh immortalwrt latest)
          
          echo "openwrt_latest=$OPENWRT_LATEST" >> $GITHUB_OUTPUT
          echo "immortalwrt_latest=$IMMORTALWRT_LATEST" >> $GITHUB_OUTPUT

      # ----- 步驟 2：同步設備庫並直接改寫 Action 選單 -----
      - name: 執行設備資料庫同步與選單注入腳本
        run: |
          chmod +x shell/sync-devices.py
          python3 shell/sync-devices.py

      # ----- 步驟 3：檢測變更並自動 Commit & Push -----
      - name: 檢測並自動提交推送變更
        id: git_check
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          # 同時檢查 devices.json 與 build-firmware.yml 的改動
          if git diff --quiet data/devices.json .github/workflows/build-firmware.yml; then
            echo "設備資料庫與選單已是最新，無需提交變更。"
            echo "updated=false" >> $GITHUB_OUTPUT
          else
            echo "偵測到更新，正在提交變更至儲存庫..."
            git add data/devices.json .github/workflows/build-firmware.yml
            git commit -m "chore(sync): 自動同步官方最新版本與支援設備清單 [skip ci]"
            git push
            echo "updated=true" >> $GITHUB_OUTPUT
          fi

      # ----- 步驟 4：產出整合報告至 Step Summary -----
      - name: 輸出整合執行摘要
        run: |
          DEVICE_COUNT=$(jq 'keys | length' data/devices.json 2>/dev/null || echo "0")
          
          echo "## 🚀 官方上游同步報告" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### 🌐 官方最新正式版本" >> $GITHUB_STEP_SUMMARY
          echo "| 韌體分支 | 最新穩定版本號 |" >> $GITHUB_STEP_SUMMARY
          echo "| :--- | :--- |" >> $GITHUB_STEP_SUMMARY
          echo "| **OpenWrt** | \`${{ steps.versions.outputs.openwrt_latest }}\` |" >> $GITHUB_STEP_SUMMARY
          echo "| **ImmortalWrt** | \`${{ steps.versions.outputs.immortalwrt_latest }}\` |" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### 📱 支援設備資料庫狀態" >> $GITHUB_STEP_SUMMARY
          echo "- **當前支援設備總數**: $DEVICE_COUNT 款" >> $GITHUB_STEP_SUMMARY
          if [ "${{ steps.git_check.outputs.updated }}" = "true" ]; then
            echo "- **選單更新狀態**: ✅ 已自動同步最新設備並更新 Action 下拉選單" >> $GITHUB_STEP_SUMMARY
          else
            echo "- **選單更新狀態**: ℹ️ 目前已是最新狀態，無須變更" >> $GITHUB_STEP_SUMMARY
          fi

````

## File: data/devices.json
````json
{
  "x86_generic": {
    "name": "[x86] 標準軟路由 / 工控機 (N100, J4125) / 虛擬機 (PVE, ESXi, PC)",
    "target": "x86/64",
    "profile": "generic"
  },
  "x86_legacy": {
    "name": "[x86] 傳統 BIOS 引導舊主機 (Legacy MBR)",
    "target": "x86/64",
    "profile": "legacy"
  },
  "nanopi_r2s": {
    "name": "[NanoPi] 友善 NanoPi R2S",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2s"
  },
  "nanopi_r2c": {
    "name": "[NanoPi] 友善 NanoPi R2C",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c"
  },
  "nanopi_r4s": {
    "name": "[NanoPi] 友善 NanoPi R4S",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s"
  },
  "nanopi_r4se": {
    "name": "[NanoPi] 友善 NanoPi R4SE",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4se"
  },
  "nanopi_r5s": {
    "name": "[NanoPi] 友善 NanoPi R5S",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5s"
  },
  "nanopi_r5c": {
    "name": "[NanoPi] 友善 NanoPi R5C",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5c"
  },
  "nanopi_r6s": {
    "name": "[NanoPi] 友善 NanoPi R6S",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6s"
  },
  "nanopi_r6c": {
    "name": "[NanoPi] 友善 NanoPi R6C",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6c"
  },
  "rpi_4": {
    "name": "[樹莓派] Raspberry Pi 4 Model B / CM4",
    "target": "bcm27xx/bcm2711",
    "profile": "rpi-4"
  },
  "rpi_5": {
    "name": "[樹莓派] Raspberry Pi 5",
    "target": "bcm27xx/bcm2712",
    "profile": "rpi-5"
  },
  "rpi_3": {
    "name": "[樹莓派] Raspberry Pi 3 Model B / B+",
    "target": "bcm27xx/bcm2710",
    "profile": "rpi-3"
  },
  "redmi_ax6000": {
    "name": "[紅米] Redmi AX6000 (MT7986)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000"
  },
  "xiaomi_ax3000t": {
    "name": "[小米] 小米路由器 AX3000T",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t"
  },
  "xiaomi_wr30u": {
    "name": "[小米] 小米路由器 WR30U",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u"
  },
  "redmi_ax3200": {
    "name": "[紅米] Redmi AX3200 / 小米 AX6S",
    "target": "mediatek/mt7622",
    "profile": "xiaomi_redmi-router-ax3200"
  },
  "xiaomi_4a_gigabit": {
    "name": "[小米] 小米路由器 4A 千兆版 (Gigabit)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit"
  },
  "glinet_mt3000": {
    "name": "[GL.iNet] GL-MT3000 (Beryl AX)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt3000"
  },
  "glinet_mt6000": {
    "name": "[GL.iNet] GL-MT6000 (Flint 2)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt6000"
  },
  "glinet_mt2500": {
    "name": "[GL.iNet] GL-MT2500 / MT2500A (Brume 2)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt2500"
  },
  "glinet_axt1800": {
    "name": "[GL.iNet] GL-AXT1800 (Slate AX)",
    "target": "ipq807x/generic",
    "profile": "glinet_gl-axt1800"
  },
  "glinet_ax1800": {
    "name": "[GL.iNet] GL-AX1800 (Flint)",
    "target": "ipq807x/generic",
    "profile": "glinet_gl-ax1800"
  },
  "asus_tuf_ax4200": {
    "name": "[華碩] ASUS TUF Gaming AX4200",
    "target": "mediatek/filogic",
    "profile": "asus_tuf-gaming-ax4200"
  },
  "tplink_xdr6088": {
    "name": "[TP-Link] TL-XDR6088 雙 2.5G 路由器",
    "target": "mediatek/filogic",
    "profile": "tplink_tl-xdr6088"
  },
  "qihoo_360t7": {
    "name": "[360] 360 T7 路由器",
    "target": "mediatek/filogic",
    "profile": "qihoo_360-t7"
  },
  "jcg_q30pro": {
    "name": "[捷稀] JCG Q30 Pro",
    "target": "mediatek/filogic",
    "profile": "jcg_q30-pro"
  },
  "phicomm_k2p": {
    "name": "[斐訊] Phicomm K2P (MT7621)",
    "target": "ramips/mt7621",
    "profile": "phicomm_k2p"
  },
  "asus_rt_ac3100": {
    "name": "[ASUS] asus_rt-ac3100",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac3100"
  },
  "asus_rt_ac56u": {
    "name": "[ASUS] asus_rt-ac56u",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac56u"
  },
  "asus_rt_ac68u": {
    "name": "[ASUS] asus_rt-ac68u",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac68u"
  },
  "asus_rt_ac87u": {
    "name": "[ASUS] asus_rt-ac87u",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac87u"
  },
  "asus_rt_ac88u": {
    "name": "[ASUS] asus_rt-ac88u",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac88u"
  },
  "asus_rt_n18u": {
    "name": "[ASUS] asus_rt-n18u",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-n18u"
  },
  "xiaomi_redmi_router_ax6s": {
    "name": "[Xiaomi] xiaomi_redmi-router-ax6s",
    "target": "mediatek/mt7622",
    "profile": "xiaomi_redmi-router-ax6s"
  },
  "asus_rt_ax59u": {
    "name": "[ASUS] asus_rt-ax59u",
    "target": "mediatek/filogic",
    "profile": "asus_rt-ax59u"
  },
  "asus_tuf_ax6000": {
    "name": "[ASUS] asus_tuf-ax6000",
    "target": "mediatek/filogic",
    "profile": "asus_tuf-ax6000"
  },
  "glinet_gl_mt2500": {
    "name": "[GL.iNet] glinet_gl-mt2500",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt2500"
  },
  "glinet_gl_mt3000": {
    "name": "[GL.iNet] glinet_gl-mt3000",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt3000"
  },
  "glinet_gl_mt6000": {
    "name": "[GL.iNet] glinet_gl-mt6000",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt6000"
  },
  "glinet_gl_x3000": {
    "name": "[GL.iNet] glinet_gl-x3000",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-x3000"
  },
  "glinet_gl_xe3000": {
    "name": "[GL.iNet] glinet_gl-xe3000",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-xe3000"
  },
  "xiaomi_mi_router_ax3000t": {
    "name": "[Xiaomi] xiaomi_mi-router-ax3000t",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t"
  },
  "xiaomi_mi_router_ax3000t_ubootmod": {
    "name": "[Xiaomi] xiaomi_mi-router-ax3000t-ubootmod",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t-ubootmod"
  },
  "xiaomi_mi_router_wr30u_stock": {
    "name": "[Xiaomi] xiaomi_mi-router-wr30u-stock",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u-stock"
  },
  "xiaomi_mi_router_wr30u_ubootmod": {
    "name": "[Xiaomi] xiaomi_mi-router-wr30u-ubootmod",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u-ubootmod"
  },
  "xiaomi_redmi_router_ax6000_stock": {
    "name": "[Xiaomi] xiaomi_redmi-router-ax6000-stock",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000-stock"
  },
  "xiaomi_redmi_router_ax6000_ubootmod": {
    "name": "[Xiaomi] xiaomi_redmi-router-ax6000-ubootmod",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000-ubootmod"
  },
  "asus_onhub": {
    "name": "[ASUS] asus_onhub",
    "target": "ipq806x/chromium",
    "profile": "asus_onhub"
  },
  "xiaomi_mi_router_hd": {
    "name": "[Xiaomi] xiaomi_mi-router-hd",
    "target": "ipq806x/generic",
    "profile": "xiaomi_mi-router-hd"
  },
  "rpi_2": {
    "name": "[Raspberry Pi] rpi-2",
    "target": "bcm27xx/bcm2709",
    "profile": "rpi-2"
  },
  "rpi": {
    "name": "[Raspberry Pi] rpi",
    "target": "bcm27xx/bcm2708",
    "profile": "rpi"
  },
  "friendlyarm_nanopc_t4": {
    "name": "[FriendlyARM] friendlyarm_nanopc-t4",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopc-t4"
  },
  "friendlyarm_nanopc_t6": {
    "name": "[FriendlyARM] friendlyarm_nanopc-t6",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopc-t6"
  },
  "friendlyarm_nanopi_r2c": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r2c",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c"
  },
  "friendlyarm_nanopi_r2c_plus": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r2c-plus",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c-plus"
  },
  "friendlyarm_nanopi_r2s": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r2s",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2s"
  },
  "friendlyarm_nanopi_r3s": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r3s",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r3s"
  },
  "friendlyarm_nanopi_r4s": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r4s",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s"
  },
  "friendlyarm_nanopi_r4s_enterprise": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r4s-enterprise",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s-enterprise"
  },
  "friendlyarm_nanopi_r4se": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r4se",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4se"
  },
  "friendlyarm_nanopi_r5c": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r5c",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5c"
  },
  "friendlyarm_nanopi_r5s": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r5s",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5s"
  },
  "friendlyarm_nanopi_r6c": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r6c",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6c"
  },
  "friendlyarm_nanopi_r6s": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r6s",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6s"
  },
  "glinet_gl_mv1000": {
    "name": "[GL.iNet] glinet_gl-mv1000",
    "target": "mvebu/cortexa53",
    "profile": "glinet_gl-mv1000"
  },
  "asus_rt_ax89x": {
    "name": "[Asus] asus_rt-ax89x",
    "target": "qualcommax/ipq807x",
    "profile": "asus_rt-ax89x"
  },
  "redmi_ax6": {
    "name": "[Redmi] redmi_ax6",
    "target": "qualcommax/ipq807x",
    "profile": "redmi_ax6"
  },
  "redmi_ax6_stock": {
    "name": "[Redmi] redmi_ax6-stock",
    "target": "qualcommax/ipq807x",
    "profile": "redmi_ax6-stock"
  },
  "xiaomi_ax3600": {
    "name": "[Xiaomi] xiaomi_ax3600",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax3600"
  },
  "xiaomi_ax3600_stock": {
    "name": "[Xiaomi] xiaomi_ax3600-stock",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax3600-stock"
  },
  "xiaomi_ax9000": {
    "name": "[Xiaomi] xiaomi_ax9000",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax9000"
  },
  "asus_rp_n53": {
    "name": "[ASUS] asus_rp-n53",
    "target": "ramips/mt7620",
    "profile": "asus_rp-n53"
  },
  "asus_rt_ac51u": {
    "name": "[ASUS] asus_rt-ac51u",
    "target": "ramips/mt7620",
    "profile": "asus_rt-ac51u"
  },
  "asus_rt_ac54u": {
    "name": "[ASUS] asus_rt-ac54u",
    "target": "ramips/mt7620",
    "profile": "asus_rt-ac54u"
  },
  "asus_rt_n14u": {
    "name": "[ASUS] asus_rt-n14u",
    "target": "ramips/mt7620",
    "profile": "asus_rt-n14u"
  },
  "glinet_gl_mt300a": {
    "name": "[GL.iNet] glinet_gl-mt300a",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt300a"
  },
  "glinet_gl_mt300n": {
    "name": "[GL.iNet] glinet_gl-mt300n",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt300n"
  },
  "glinet_gl_mt750": {
    "name": "[GL.iNet] glinet_gl-mt750",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt750"
  },
  "xiaomi_miwifi_mini": {
    "name": "[Xiaomi] xiaomi_miwifi-mini",
    "target": "ramips/mt7620",
    "profile": "xiaomi_miwifi-mini"
  },
  "asus_rt_ac1200": {
    "name": "[ASUS] asus_rt-ac1200",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-ac1200"
  },
  "asus_rt_ac1200_v2": {
    "name": "[ASUS] asus_rt-ac1200-v2",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-ac1200-v2"
  },
  "asus_rt_n12_vp_b1": {
    "name": "[ASUS] asus_rt-n12-vp-b1",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-n12-vp-b1"
  },
  "glinet_gl_mt300n_v2": {
    "name": "[GL.iNet] glinet_gl-mt300n-v2",
    "target": "ramips/mt76x8",
    "profile": "glinet_gl-mt300n-v2"
  },
  "glinet_microuter_n300": {
    "name": "[GL.iNet] glinet_microuter-n300",
    "target": "ramips/mt76x8",
    "profile": "glinet_microuter-n300"
  },
  "glinet_vixmini": {
    "name": "[GL.iNet] glinet_vixmini",
    "target": "ramips/mt76x8",
    "profile": "glinet_vixmini"
  },
  "xiaomi_mi_ra75": {
    "name": "[Xiaomi] xiaomi_mi-ra75",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-ra75"
  },
  "xiaomi_mi_router_4a_100m": {
    "name": "[Xiaomi] xiaomi_mi-router-4a-100m",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m"
  },
  "xiaomi_mi_router_4a_100m_intl": {
    "name": "[Xiaomi] xiaomi_mi-router-4a-100m-intl",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m-intl"
  },
  "xiaomi_mi_router_4a_100m_intl_v2": {
    "name": "[Xiaomi] xiaomi_mi-router-4a-100m-intl-v2",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m-intl-v2"
  },
  "xiaomi_mi_router_4c": {
    "name": "[Xiaomi] xiaomi_mi-router-4c",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4c"
  },
  "xiaomi_miwifi_3c": {
    "name": "[Xiaomi] xiaomi_miwifi-3c",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_miwifi-3c"
  },
  "xiaomi_miwifi_nano": {
    "name": "[Xiaomi] xiaomi_miwifi-nano",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_miwifi-nano"
  },
  "asus_rp_ac56": {
    "name": "[ASUS] asus_rp-ac56",
    "target": "ramips/mt7621",
    "profile": "asus_rp-ac56"
  },
  "asus_rp_ac87": {
    "name": "[ASUS] asus_rp-ac87",
    "target": "ramips/mt7621",
    "profile": "asus_rp-ac87"
  },
  "asus_rt_ac57u_v1": {
    "name": "[ASUS] asus_rt-ac57u-v1",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac57u-v1"
  },
  "asus_rt_ac65p": {
    "name": "[ASUS] asus_rt-ac65p",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac65p"
  },
  "asus_rt_ac85p": {
    "name": "[ASUS] asus_rt-ac85p",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac85p"
  },
  "asus_rt_ax53u": {
    "name": "[ASUS] asus_rt-ax53u",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ax53u"
  },
  "asus_rt_ax54": {
    "name": "[ASUS] asus_rt-ax54",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ax54"
  },
  "asus_rt_n56u_b1": {
    "name": "[ASUS] asus_rt-n56u-b1",
    "target": "ramips/mt7621",
    "profile": "asus_rt-n56u-b1"
  },
  "glinet_gl_mt1300": {
    "name": "[GL.iNet] glinet_gl-mt1300",
    "target": "ramips/mt7621",
    "profile": "glinet_gl-mt1300"
  },
  "xiaomi_mi_router_3_pro": {
    "name": "[Xiaomi] xiaomi_mi-router-3-pro",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3-pro"
  },
  "xiaomi_mi_router_3g": {
    "name": "[Xiaomi] xiaomi_mi-router-3g",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3g"
  },
  "xiaomi_mi_router_3g_v2": {
    "name": "[Xiaomi] xiaomi_mi-router-3g-v2",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3g-v2"
  },
  "xiaomi_mi_router_4": {
    "name": "[Xiaomi] xiaomi_mi-router-4",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4"
  },
  "xiaomi_mi_router_4a_gigabit": {
    "name": "[Xiaomi] xiaomi_mi-router-4a-gigabit",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit"
  },
  "xiaomi_mi_router_4a_gigabit_v2": {
    "name": "[Xiaomi] xiaomi_mi-router-4a-gigabit-v2",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit-v2"
  },
  "xiaomi_mi_router_ac2100": {
    "name": "[Xiaomi] xiaomi_mi-router-ac2100",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-ac2100"
  },
  "xiaomi_mi_router_cr6606": {
    "name": "[Xiaomi] xiaomi_mi-router-cr6606",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6606"
  },
  "xiaomi_mi_router_cr6608": {
    "name": "[Xiaomi] xiaomi_mi-router-cr6608",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6608"
  },
  "xiaomi_mi_router_cr6609": {
    "name": "[Xiaomi] xiaomi_mi-router-cr6609",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6609"
  },
  "xiaomi_redmi_router_ac2100": {
    "name": "[Xiaomi] xiaomi_redmi-router-ac2100",
    "target": "ramips/mt7621",
    "profile": "xiaomi_redmi-router-ac2100"
  },
  "asus_map_ac2200": {
    "name": "[ASUS] asus_map-ac2200",
    "target": "ipq40xx/generic",
    "profile": "asus_map-ac2200"
  },
  "asus_rt_ac42u": {
    "name": "[ASUS] asus_rt-ac42u",
    "target": "ipq40xx/generic",
    "profile": "asus_rt-ac42u"
  },
  "asus_rt_ac58u": {
    "name": "[ASUS] asus_rt-ac58u",
    "target": "ipq40xx/generic",
    "profile": "asus_rt-ac58u"
  },
  "glinet_gl_a1300": {
    "name": "[GL.iNet] glinet_gl-a1300",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-a1300"
  },
  "glinet_gl_ap1300": {
    "name": "[GL.iNet] glinet_gl-ap1300",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-ap1300"
  },
  "glinet_gl_b1300": {
    "name": "[GL.iNet] glinet_gl-b1300",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-b1300"
  },
  "glinet_gl_b2200": {
    "name": "[GL.iNet] glinet_gl-b2200",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-b2200"
  },
  "friendlyarm_nanopi_neo_plus2": {
    "name": "[FriendlyARM] friendlyarm_nanopi-neo-plus2",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-neo-plus2"
  },
  "friendlyarm_nanopi_neo2": {
    "name": "[FriendlyARM] friendlyarm_nanopi-neo2",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-neo2"
  },
  "friendlyarm_nanopi_r1s_h5": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r1s-h5",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-r1s-h5"
  },
  "friendlyarm_nanopi_m1_plus": {
    "name": "[FriendlyARM] friendlyarm_nanopi-m1-plus",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-m1-plus"
  },
  "friendlyarm_nanopi_neo": {
    "name": "[FriendlyARM] friendlyarm_nanopi-neo",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-neo"
  },
  "friendlyarm_nanopi_neo_air": {
    "name": "[FriendlyARM] friendlyarm_nanopi-neo-air",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-neo-air"
  },
  "friendlyarm_nanopi_r1": {
    "name": "[FriendlyARM] friendlyarm_nanopi-r1",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-r1"
  },
  "friendlyarm_zeropi": {
    "name": "[FriendlyARM] friendlyarm_zeropi",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_zeropi"
  },
  "glinet_gl_ar300m_nand": {
    "name": "[GL.iNet] glinet_gl-ar300m-nand",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar300m-nand"
  },
  "glinet_gl_ar300m_nor": {
    "name": "[GL.iNet] glinet_gl-ar300m-nor",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar300m-nor"
  },
  "glinet_gl_ar750s_nor": {
    "name": "[GL.iNet] glinet_gl-ar750s-nor",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar750s-nor"
  },
  "glinet_gl_ar750s_nor_nand": {
    "name": "[GL.iNet] glinet_gl-ar750s-nor-nand",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar750s-nor-nand"
  },
  "glinet_gl_e750": {
    "name": "[GL.iNet] glinet_gl-e750",
    "target": "ath79/nand",
    "profile": "glinet_gl-e750"
  },
  "glinet_gl_s200_nor": {
    "name": "[GL.iNet] glinet_gl-s200-nor",
    "target": "ath79/nand",
    "profile": "glinet_gl-s200-nor"
  },
  "glinet_gl_s200_nor_nand": {
    "name": "[GL.iNet] glinet_gl-s200-nor-nand",
    "target": "ath79/nand",
    "profile": "glinet_gl-s200-nor-nand"
  },
  "glinet_gl_x1200_nor": {
    "name": "[GL.iNet] glinet_gl-x1200-nor",
    "target": "ath79/nand",
    "profile": "glinet_gl-x1200-nor"
  },
  "glinet_gl_x1200_nor_nand": {
    "name": "[GL.iNet] glinet_gl-x1200-nor-nand",
    "target": "ath79/nand",
    "profile": "glinet_gl-x1200-nor-nand"
  },
  "glinet_gl_xe300": {
    "name": "[GL.iNet] glinet_gl-xe300",
    "target": "ath79/nand",
    "profile": "glinet_gl-xe300"
  },
  "asus_pl_ac56": {
    "name": "[ASUS] asus_pl-ac56",
    "target": "ath79/generic",
    "profile": "asus_pl-ac56"
  },
  "asus_rp_ac51": {
    "name": "[ASUS] asus_rp-ac51",
    "target": "ath79/generic",
    "profile": "asus_rp-ac51"
  },
  "asus_rp_ac66": {
    "name": "[ASUS] asus_rp-ac66",
    "target": "ath79/generic",
    "profile": "asus_rp-ac66"
  },
  "asus_rt_ac59u": {
    "name": "[ASUS] asus_rt-ac59u",
    "target": "ath79/generic",
    "profile": "asus_rt-ac59u"
  },
  "asus_rt_ac59u_v2": {
    "name": "[ASUS] asus_rt-ac59u-v2",
    "target": "ath79/generic",
    "profile": "asus_rt-ac59u-v2"
  },
  "asus_zenwifi_cd6n": {
    "name": "[ASUS] asus_zenwifi-cd6n",
    "target": "ath79/generic",
    "profile": "asus_zenwifi-cd6n"
  },
  "asus_zenwifi_cd6r": {
    "name": "[ASUS] asus_zenwifi-cd6r",
    "target": "ath79/generic",
    "profile": "asus_zenwifi-cd6r"
  },
  "glinet_6408": {
    "name": "[GL.iNet] glinet_6408",
    "target": "ath79/generic",
    "profile": "glinet_6408"
  },
  "glinet_6416": {
    "name": "[GL.iNet] glinet_6416",
    "target": "ath79/generic",
    "profile": "glinet_6416"
  },
  "glinet_gl_ar150": {
    "name": "[GL.iNet] glinet_gl-ar150",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar150"
  },
  "glinet_gl_ar300m_lite": {
    "name": "[GL.iNet] glinet_gl-ar300m-lite",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar300m-lite"
  },
  "glinet_gl_ar300m16": {
    "name": "[GL.iNet] glinet_gl-ar300m16",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar300m16"
  },
  "glinet_gl_ar750": {
    "name": "[GL.iNet] glinet_gl-ar750",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar750"
  },
  "glinet_gl_mifi": {
    "name": "[GL.iNET] glinet_gl-mifi",
    "target": "ath79/generic",
    "profile": "glinet_gl-mifi"
  },
  "glinet_gl_usb150": {
    "name": "[GL.iNET] glinet_gl-usb150",
    "target": "ath79/generic",
    "profile": "glinet_gl-usb150"
  },
  "glinet_gl_x300b": {
    "name": "[GL.iNet] glinet_gl-x300b",
    "target": "ath79/generic",
    "profile": "glinet_gl-x300b"
  },
  "glinet_gl_x750": {
    "name": "[GL.iNet] glinet_gl-x750",
    "target": "ath79/generic",
    "profile": "glinet_gl-x750"
  },
  "xiaomi_aiot_ac2350": {
    "name": "[Xiaomi] xiaomi_aiot-ac2350",
    "target": "ath79/generic",
    "profile": "xiaomi_aiot-ac2350"
  },
  "xiaomi_mi_router_4q": {
    "name": "[Xiaomi] xiaomi_mi-router-4q",
    "target": "ath79/generic",
    "profile": "xiaomi_mi-router-4q"
  },
  "asus_rt_ac53u": {
    "name": "[ASUS] asus_rt-ac53u",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-ac53u"
  },
  "asus_rt_n14uhp": {
    "name": "[ASUS] asus_rt-n14uhp",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n14uhp"
  },
  "asus_rt_n15u": {
    "name": "[ASUS] asus_rt-n15u",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n15u"
  },
  "asus_rt_n16": {
    "name": "[ASUS] asus_rt-n16",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n16"
  },
  "asus_rt_n66u": {
    "name": "[ASUS] asus_rt-n66u",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n66u"
  },
  "asus_rt_n66w": {
    "name": "[ASUS] asus_rt-n66w",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n66w"
  },
  "asus_gt_ac5300": {
    "name": "[ASUS] asus_gt-ac5300",
    "target": "bcm4908/generic",
    "profile": "asus_gt-ac5300"
  },
  "asus_rt_n56u": {
    "name": "[ASUS] asus_rt-n56u",
    "target": "ramips/rt3883",
    "profile": "asus_rt-n56u"
  }
}
````

## File: README.md
````md
# OpenWrt & ImmortalWrt 雙核心雲端韌體構建工具

本專案提供基於 GitHub Actions CI 的快速雲端 ImageBuilder 自動化構建方案。無需繁複的本地 Linux 交叉編譯環境，可在 5~8 分鐘內快速打包出專屬固件。

---

### ✨ 特性亮點
- 🔄 **雙分支選擇**：自由切換構建 **OpenWrt** 官方原版或 **ImmortalWrt** 衍生版。
- 🔍 **自動版本讀取**：版本欄位預設為 `auto`，自動向官方查詢並下載最新釋出的穩定版本。
- 💾 **自訂軟體包空間大小**：以 **GB (G)** 為單位，直接輸入數字即可自訂系統空間（如 `1`、`2`、`4`）。
- 🇹🇼 **繁體中文原廠化**：完整繁體中文介面、預載 `zh-tw` 語系、首次開機自動套用繁體中文。
- 🐳 **可選 Docker 支援**：支援一鍵勾選預裝 Docker 核心與 Dockerman 視覺化管理介面。
- 🌐 **智慧網路與 PPPoE**：單網口設備自動 DHCP 獲取 IP；多網口機型預設 LAN 為 `192.168.100.1`，支援預設寬頻撥號。

---

### 🚀 快速上手步驟

1. **Fork 本儲存庫** 到您自己的 GitHub 帳號。
2. 進入您 Fork 後的專案頁面，點選上方的 **Actions** 標籤。
3. 在左側清單點選 **構建 OpenWrt / ImmortalWrt 自訂韌體**，點擊右側的 **Run workflow**。
4. 於彈出表單中填寫您的偏好：
   - **韌體系統分支**：選擇 `ImmortalWrt` 或 `OpenWrt`。
   - **韌體版本**：預設為 `auto`（自動選定最新穩定版），亦可指定版本（例如 `24.10.0`）。
   - **軟體包分區空間大小**：直接輸入數字，例如 `2` 代表 2GB 空間。
   - **是否整合 Docker**：勾選即可帶入 Docker 容器環境。
5. 點擊綠色按鈕 **Run workflow**，約 5~7 分鐘即可在執行摘要頁面下載打包完成的韌體！

---

### 📦 自訂額外外掛

如需自訂集成更多軟體包或移除特定套件，直接編輯倉庫中的 `shell/custom-packages.sh`：
- **新增套件**：添加 `CUSTOM_PACKAGES="$CUSTOM_PACKAGES 軟體包名稱"`
- **移除套件**：添加減號前綴，例如 `-luci-app-samba4`

#### 🔍 官方外掛與軟體包線上查找網址

在添加外掛前，建議至下列官方資料庫確認套件確切名稱：

1. **OpenWrt 官方資料庫**：
   - [OpenWrt 官方全套件即時搜尋表 (Package Table)](https://openwrt.org/packages/table/start)：可依照關鍵字、架構檢索所有官方收錄的套件。
   - [OpenWrt 官方韌體選擇器 (Firmware Selector)](https://firmware-selector.openwrt.org/)：在「Installed Packages」欄位可直接搜尋外掛並即時查看依賴關係。
   - [OpenWrt 官方 LuCI 外掛源碼總覽 (GitHub)](https://github.com/openwrt/luci/tree/master/applications)：瀏覽所有官方支援的 `luci-app-*` 插件。

2. **ImmortalWrt 資料庫（特色功能與國內優化插件）**：
   - [ImmortalWrt 韌體選擇器 (Firmware Selector)](https://firmware-selector.immortalwrt.org/)：輸入型號後可在套件清單中直接搜尋 ImmortalWrt 專屬外掛。
   - [ImmortalWrt LuCI 外掛源碼總覽 (GitHub)](https://github.com/immortalwrt/luci/tree/master/applications)：查看 ImmortalWrt 額外收錄的進階插件（如 TurboACC、各類網路優化等）。

> 💡 **小提示 (繁體中文支援)**：
> 若安裝了以 `luci-app-<名稱>` 開頭的圖形介面外掛，建議同時加上對應的繁體中文語言包 `luci-i18n-<名稱>-zh-tw`（例如：`luci-app-ttyd` 搭配 `luci-i18n-ttyd-zh-tw`）。

````

