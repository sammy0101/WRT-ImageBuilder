# Complete Project Codebase
Generated on: Sun Sep 27 08:31:47 UTC 2026

## File: files/etc/uci-defaults/99-custom.sh
````sh
#!/bin/sh
# ==============================================================================
# 首航初始化腳本：開機首次啟動自動執行一次後自我銷毀
# ==============================================================================

LOG_FILE="/tmp/uci-defaults-init.log"
echo "=== 開始執行首航網路與系統配置 $(date) ===" > "$LOG_FILE"

# 1. 讀取自訂網路參數設定檔
NET_CONF="/etc/custom_network_config"
if [ -f "$NET_CONF" ]; then
    . "$NET_CONF"
fi

TARGET_LAN_IP="${CUSTOM_LAN_IP:-192.168.100.1}"
IS_BYPASS="${IS_BYPASS_ROUTER:-false}"
GATEWAY="${GATEWAY_IP:-192.168.100.1}"
DNS_LIST="${DNS_SERVERS:-192.168.100.1 8.8.8.8}"

# 2. 網路配置 (旁路由 vs 主路由模式)
if [ "$IS_BYPASS" = "true" ]; then
    echo "==========================================================" >> "$LOG_FILE"
    echo "  正在套用【旁路由模式】配置..." >> "$LOG_FILE"
    echo "  本機 IP: $TARGET_LAN_IP" >> "$LOG_FILE"
    echo "  主路由網關: $GATEWAY" >> "$LOG_FILE"
    echo "  自訂 DNS: $DNS_LIST" >> "$LOG_FILE"
    echo "==========================================================" >> "$LOG_FILE"

    # (A) 配置 LAN 靜態 IP、網關與 DNS
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$GATEWAY"
    
    # 遍歷加入 DNS 清單
    uci -q delete network.lan.dns
    for dns_ip in $DNS_LIST; do
        uci add_list network.lan.dns="$dns_ip"
    done

    # (B) 【最重要】關閉旁路由的 DHCP 伺服器 (防止與主路由器衝突)
    uci set dhcp.lan.ignore='1'
    uci -q delete dhcp.lan.dhcpv6
    uci -q delete dhcp.lan.ra
    uci -q delete dhcp.lan.ra_slaac
    uci -q delete dhcp.lan.ra_flags

    # (C) 【最重要】開啟 LAN 防火牆動態偽裝 (NAT Masquerade)，解決單向流量問題
    uci set firewall.@zone[0].masq='1'
    uci set firewall.@zone[0].mtu_fix='1'

    # (D) 旁路由通常不需要獨立 WAN 接口，停用避免衝突
    uci set network.wan.disabled='1' 2>/dev/null || true
    uci set network.wan6.disabled='1' 2>/dev/null || true

else
    echo "套用【標準主路由模式】: LAN IP=$TARGET_LAN_IP" >> "$LOG_FILE"
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    uci set dhcp.lan.ignore='0'

    # PPPoE 撥號配置
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
fi

# 3. 防火牆允許入站訪問
uci set firewall.@zone[1].input='ACCEPT' 2>/dev/null || true

uci commit network
uci commit dhcp
uci commit firewall

# 4. 【註冊與啟用 DAED】
if [ -f "/usr/bin/daed" ] || [ -f "/etc/init.d/daed" ]; then
    echo "正在初始化 DAED 配置與自啟動服務..." >> "$LOG_FILE"
    mkdir -p /etc/daed /var/log/daed
    chmod +x /usr/bin/daed 2>/dev/null || true
    chmod +x /etc/init.d/daed 2>/dev/null || true
    
    /etc/init.d/daed enable 2>/dev/null || true
    /etc/init.d/daed restart 2>/dev/null || true
    
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
fi

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
# 自訂擴充軟體包選單 (官方原版英文介面)
# ==============================================================================

CUSTOM_PACKAGES=""

# 核心 Web UI
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"

# 介面主題
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon"

# 依賴組件
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ca-bundle kmod-tun"

# 若需要代理，原版 OpenWrt 推薦使用 OpenClash 或 PassWall (不需要內核 BTF)
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
# CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-passwall"

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
# 支援 旁路由引導模式 + OpenWrt 原版預裝 DAED (自帶 LuCI 選單與二進制)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-25.12.5}"
SELECTED_DEVICE="${DEVICE_MODEL:-x86_generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
IS_BYPASS="${IS_BYPASS_ROUTER:-false}"
TARGET_IP="${LAN_IP:-192.168.100.1}"
GW_IP="${GATEWAY_IP:-192.168.100.2}"
DNS_IPS="${DNS_SERVERS:-192.168.100.2 8.8.8.8}"
PPPOE_EN="${ENABLE_PPPOE:-false}"

# 1. 解析設備鍵名
DEVICE_KEY=$(echo "$SELECTED_DEVICE" | cut -d':' -f1 | tr -d ' ')
DEVICES_FILE="$ROOT_DIR/data/devices.json"

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
echo "  開始構建雲端自訂韌體 (英文原生版)"
echo "  系統類型: $FW_TYPE"
echo "  系統版本: $FW_VER"
echo "  所選設備: $DEVICE_KEY"
echo "  目標架構 (Target): $TARGET_INPUT"
echo "  設備代號 (Profile): $PROFILE_NAME"
echo "  網路模式: $([ "$IS_BYPASS" = "true" ] && echo "🛡️ 旁路由模式" || echo "🌐 主路由模式")"
echo "  本機 LAN IP: $TARGET_IP"
if [ "$IS_BYPASS" = "true" ]; then
  echo "  主路由網關: $GW_IP"
  echo "  自訂 DNS: $DNS_IPS"
fi
echo "  設定容量: $SIZE_IN_GB GB"
echo "=========================================================="

# 2. 驗證容量並換算為 MB
if ! [[ "$SIZE_IN_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "錯誤: 輸入的空間大小必須為數字！當前值: '$SIZE_IN_GB'" >&2
  exit 1
fi
PARTSIZE_MB=$(awk -v gb="$SIZE_IN_GB" 'BEGIN { printf "%.0f", gb * 1024 }')
echo "✓ 軟體包分區已轉換: ${SIZE_IN_GB} GB -> ${PARTSIZE_MB} MB"

IFS='/' read -r TARGET_DIR SUBTARGET_DIR <<< "$TARGET_INPUT"

# 3. 下載官方 ImageBuilder
if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  BASE_URL="https://downloads.openwrt.org/releases/${FW_VER}/targets/${TARGET_DIR}/${SUBTARGET_DIR}"
  ARCHIVE_NAME="openwrt-imagebuilder-${FW_VER}-${TARGET_DIR}-${SUBTARGET_DIR}.Linux-x86_64.tar.zst"
else
  BASE_URL="https://downloads.immortalwrt.org/releases/${FW_VER}/targets/${TARGET_DIR}/${SUBTARGET_DIR}"
  ARCHIVE_NAME="immortalwrt-imagebuilder-${FW_VER}-${TARGET_DIR}-${SUBTARGET_DIR}.Linux-x86_64.tar.zst"
fi

WORKDIR="$ROOT_DIR/build_workspace"
OUTPUT_DIR="$ROOT_DIR/output"
mkdir -p "$WORKDIR" "$OUTPUT_DIR"

echo "下載官方 ImageBuilder: $BASE_URL/$ARCHIVE_NAME"
if ! wget -q -c --timeout=30 --tries=3 "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"; then
  ARCHIVE_NAME="${ARCHIVE_NAME%.zst}.xz"
  echo "嘗試 .tar.xz 備用格式: $BASE_URL/$ARCHIVE_NAME"
  wget -c --timeout=30 --tries=3 "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"
fi

echo "正在解壓縮 ImageBuilder..."
tar -xf "$WORKDIR/$ARCHIVE_NAME" -C "$WORKDIR"
EXTRACTED_DIR=$(find "$WORKDIR" -maxdepth 1 -type d -name "*imagebuilder*" | head -n 1)
cd "$EXTRACTED_DIR"

# 4. 讀取並整合軟體包清單
source "$ROOT_DIR/shell/custom-packages.sh"
PACKAGES_TO_BUILD="$CUSTOM_PACKAGES"

if [[ "$DOCKER_FLAG" == "true" ]]; then
  echo "✓ 已勾選整合 Docker 與 Dockerman 管理套件"
  PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD docker dockerd docker-compose luci-app-dockerman"
fi

is_apk=false
if [[ "$FW_VER" =~ ^25\. ]] || [ -f "staging_dir/host/bin/apk" ]; then
  is_apk=true
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-i18n-opkg-zh-tw//g; s/luci-app-opkg//g')
fi

# 5. 整合 Overlay 檔案 (files 系統覆蓋層)
mkdir -p files/etc/uci-defaults files/etc/config
cp -r "$ROOT_DIR/files/"* files/

cat <<EOF > files/etc/custom_network_config
CUSTOM_LAN_IP="$TARGET_IP"
IS_BYPASS_ROUTER="$IS_BYPASS"
GATEWAY_IP="$GW_IP"
DNS_SERVERS="$DNS_IPS"
EOF

if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 【DAED 與 Argon 完整注入】
DAED_PREINSTALLED=false
mkdir -p packages

if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  echo ""
  echo "=========================================================="
  echo "  正在處理 OpenWrt 第三方外掛 (DAED & Argon)..."
  echo "=========================================================="

  # (A) 下載相容的 luci-theme-argon
  if [[ " $PACKAGES_TO_BUILD " =~ " luci-theme-argon " ]]; then
    echo "下載 luci-theme-argon 安裝包..."
    if [ "$is_apk" = true ]; then
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon-2.4.7-r1.apk"
    else
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7-1_all.ipk"
    fi
    wget -q -c --timeout=20 --tries=3 "$ARGON_URL" -P packages/ || true
  fi

  # (B) daed 與 luci-app-daed：真·官方倉庫精準下載與提取
  if [[ " $PACKAGES_TO_BUILD " =~ " daed " ]]; then
    echo "正在下載 DAED 核心與官方 LuCI 介面組件..."
    mkdir -p /tmp/daed_pkgs files/usr/bin files/etc/init.d files/etc/daed

    if [ "$is_apk" = true ]; then
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed-2026.07.31-r1-x86_64-openwrt-25.12.apk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed-1.4-r1-openwrt-25.12.apk"
    else
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed_2026.07.31-r1_x86_64-openwrt-24.10.ipk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed_1.4-r1_all-openwrt-24.10.ipk"
    fi

    echo "下載 DAED 核心: $DAED_BIN_URL"
    curl -fL -sS --connect-timeout 30 --retry 3 "$DAED_BIN_URL" -o /tmp/daed_pkgs/daed.pkg || echo "⚠️ 下載 DAED 核心失敗"

    echo "下載 DAED LuCI: $DAED_LUCI_URL"
    curl -fL -sS --connect-timeout 30 --retry 3 "$DAED_LUCI_URL" -o /tmp/daed_pkgs/luci.pkg || echo "⚠️ 下載 DAED LuCI 失敗"

    echo "檢驗暫存檔案大小:"
    ls -lh /tmp/daed_pkgs/ || true

    echo "正在使用 ImageBuilder 官方 host apk 工具提取組件..."
    for p_file in /tmp/daed_pkgs/*.pkg; do
      [ -s "$p_file" ] || continue
      
      # 調用編譯器自帶的 host apk 解包
      if [ "$is_apk" = true ] && [ -x "staging_dir/host/bin/apk" ]; then
        echo "官方工具提取: $(basename "$p_file")..."
        ./staging_dir/host/bin/apk extract --allow-untrusted --destination "$PWD/files/" "$p_file" || true
      fi
      
      # 針對 ipk 或 7z 備用解包
      if command -v 7z >/dev/null 2>&1; then
        mkdir -p /tmp/7z_ext
        7z x -y "$p_file" -o/tmp/7z_ext/ >/dev/null 2>&1 || true
        if [ -f "/tmp/7z_ext/data.tar.gz" ]; then
          tar -xzf /tmp/7z_ext/data.tar.gz -C "$PWD/files/" 2>/dev/null || true
        fi
        cp -rf /tmp/7z_ext/* "$PWD/files/" 2>/dev/null || true
        rm -rf /tmp/7z_ext
      fi
    done

    rm -rf files/.PKGINFO files/.SIGN.* files/control.tar.gz files/data.tar.gz files/debian-binary /tmp/daed_pkgs 2>/dev/null || true
    chmod +x files/usr/bin/daed files/etc/init.d/daed 2>/dev/null || true

    # 實體檢驗
    if [ -f "files/usr/bin/daed" ]; then
      echo "✓【驗證成功】/usr/bin/daed 核心二進制已寫入！大小: $(ls -lh files/usr/bin/daed | awk '{print $5}')"
      DAED_PREINSTALLED=true
    else
      echo "❌【警告】未能成功解出 files/usr/bin/daed"
    fi

    if [ -f "files/usr/share/luci/menu.d/luci-app-daed.json" ]; then
      echo "✓【驗證成功】LuCI 官方選單定義 (luci-app-daed.json) 已就位！"
    fi

    PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD kmod-tun ca-bundle"
    PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/daed//g; s/luci-app-daed//g; s/vmlinux-btf//g')
  fi

  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-app-turboacc//g')
  echo "=========================================================="
  echo ""
fi

PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | xargs)
echo "最終交給套件管理器的軟體包列表: $PACKAGES_TO_BUILD"

# 7. 打包構建
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
    
    local record_pkgs="$current_pkgs"
    if [ "$DAED_PREINSTALLED" = true ]; then
      record_pkgs="$record_pkgs daed"
    fi
    echo "$record_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' > "$OUTPUT_DIR/custom_packages.txt"
    return 0
  fi

  # 容錯自癒機制
  local missing_pkgs=$(grep -E '^\s+[a-zA-Z0-9_\.\-]+ \(no such package\):' "$log_tmp" | awk '{print $1}' | tr '\n' ' ')
  local parent_raw=$(grep -oE '[a-zA-Z0-9_\.\-]+\[[^]]+\]' "$log_tmp" | cut -d'[' -f1 | grep -v '^world$' | tr '\n' ' ')
  local parent_clean=""
  for p in $parent_raw; do
    c_name=$(echo "$p" | sed -E 's/-[0-9].*//; s/_[0-9].*//')
    parent_clean="$parent_clean $c_name"
  done

  local missing_opkg=$(grep -oE "Unknown package '[^']+'" "$log_tmp" | cut -d"'" -f2 | tr '\n' ' ')
  local missing_opkg2=$(grep -oE "Cannot install package [^.]+" "$log_tmp" | awk '{print $NF}' | tr '\n' ' ')

  local all_culprits=$(echo "$missing_pkgs $parent_clean $missing_opkg $missing_opkg2" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || echo "")

  if [ -n "$all_culprits" ]; then
    echo "⚠️ 剔除不可用套件: $all_culprits 並重試..."
    local cleaned_pkgs="$current_pkgs"
    for item in $all_culprits; do
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )$item( |\$)/ /g")
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )luci-app-$item( |\$)/ /g")
      rm -f packages/*"$item"* 2>/dev/null || true
    done
    cleaned_pkgs=$(echo "$cleaned_pkgs" | xargs)

    if make image \
      PROFILE="$PROFILE_NAME" \
      PACKAGES="$cleaned_pkgs" \
      FILES="files" \
      ROOTFS_PARTSIZE="$PARTSIZE_MB" \
      BIN_DIR="$OUTPUT_DIR"; then
      local record_pkgs="$cleaned_pkgs"
      if [ "$DAED_PREINSTALLED" = true ]; then
        record_pkgs="$record_pkgs daed"
      fi
      echo "$record_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' > "$OUTPUT_DIR/custom_packages.txt"
      return 0
    fi
    return 1
  fi

  return 1
}

execute_make_image "$PACKAGES_TO_BUILD"

# 8. 自動轉換 VMware .vmdk 虛擬磁碟格式
if ls "$OUTPUT_DIR"/*combined* 1> /dev/null 2>&1; then
  echo "正在生成 VMware .vmdk 虛擬磁碟..."
  for img_gz in "$OUTPUT_DIR"/*combined*.img.gz; do
    [ -f "$img_gz" ] || continue
    base_name=$(basename "$img_gz" .img.gz)
    raw_tmp="/tmp/${base_name}.img"
    vmdk_target="$OUTPUT_DIR/${base_name}.vmdk"

    gzip -dc "$img_gz" > "$raw_tmp"
    qemu-img convert -f raw -O vmdk "$raw_tmp" "$vmdk_target"
    rm -f "$raw_tmp"
  done
  echo "✓ VMware .vmdk 轉換完成！"
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
        default: 'OpenWrt'
        options:
          - 'OpenWrt'
          - 'ImmortalWrt'

      luci_version:
        description: '韌體版本 (預設 auto 自動抓取最新正式版；亦可手動輸入如: 25.12.5, 24.10.0)'
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
          # --- AUTO_DEVICES_END ---

      is_bypass_router:
        description: '【旁路由開關】是否作為旁路由 / 二級網關模式 (預設不開啟；勾選為開啟)'
        required: false
        type: boolean
        default: false

      lan_ip:
        description: '本機 LAN IP (主路由預設 192.168.100.1；若為旁路由請輸入同網段固定 IP 如 192.168.100.1)'
        required: false
        default: '192.168.100.1'
        type: string

      gateway_ip:
        description: '【旁路由專用】主路由器網關 IP (旁路由需指向主路由 IP，例如: 192.168.100.2)'
        required: false
        default: '192.168.100.2'
        type: string

      dns_servers:
        description: '【旁路由專用】自訂 DNS 伺服器 (多個請用空格分開，例如: 192.168.100.2 8.8.8.8)'
        required: false
        default: '192.168.100.2 8.8.8.8'
        type: string

      include_docker:
        description: '是否整合 Docker 與 Dockerman 容器介面'
        required: false
        type: boolean
        default: false

      enable_pppoe:
        description: '【主路由專用】是否啟用 WAN 端 PPPoE 撥號 (旁路由請保持 false)'
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

      - name: 安裝編譯相依套件
        run: |
          sudo apt-get update
          sudo apt-get install -y build-essential libncurses5-dev zlib1g-dev gawk git \
            gettext libssl-dev xsltproc wget unzip python3 zstd file jq curl qemu-utils \
            genisoimage dosfstools mtools xorriso p7zip-full
          
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
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          FIRMWARE_TYPE: ${{ inputs.firmware_type }}
          VERSION: ${{ steps.resolve_version.outputs.version }}
          DEVICE_MODEL: ${{ inputs.device_model }}
          ROOTFS_SIZE_G: ${{ inputs.rootfs_size_g }}
          INCLUDE_DOCKER: ${{ inputs.include_docker }}
          IS_BYPASS_ROUTER: ${{ inputs.is_bypass_router }}
          LAN_IP: ${{ inputs.lan_ip }}
          GATEWAY_IP: ${{ inputs.gateway_ip }}
          DNS_SERVERS: ${{ inputs.dns_servers }}
          ENABLE_PPPOE: ${{ inputs.enable_pppoe }}
          PPPOE_ACCOUNT: ${{ inputs.pppoe_account }}
          PPPOE_PASSWORD: ${{ inputs.pppoe_password }}
        run: |
          chmod +x build.sh
          chmod +x shell/custom-packages.sh
          chmod +x files/etc/uci-defaults/99-custom.sh
          ./build.sh

      - name: 產生校驗碼、外掛清單與構建摘要
        id: summary
        run: |
          cd output
          sha256sum * > sha256sums.txt
          
          if [ -f custom_packages.txt ]; then
            PKGS_MD=$(sed 's/^/- `/' custom_packages.txt | sed 's/$/`/')
          else
            PKGS_MD="- 官方標準基礎組件"
          fi
          
          echo "### 構建成果摘要 🚀" >> $GITHUB_STEP_SUMMARY
          echo "- **系統分支**: ${{ inputs.firmware_type }}" >> $GITHUB_STEP_SUMMARY
          echo "- **固件版本**: ${{ steps.resolve_version.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **設備型號**: ${{ inputs.device_model }}" >> $GITHUB_STEP_SUMMARY
          echo "- **軟體包分區大小**: ${{ inputs.rootfs_size_g }} GB" >> $GITHUB_STEP_SUMMARY
          if [ "${{ inputs.is_bypass_router }}" = "true" ]; then
            echo "- **網路模式**: 🛡️ 旁路由 / 網關模式 (已關閉 DHCP，啟用 NAT 偽裝)" >> $GITHUB_STEP_SUMMARY
            echo "- **本機 LAN IP**: http://${{ inputs.lan_ip }}" >> $GITHUB_STEP_SUMMARY
            echo "- **主路由網關**: ${{ inputs.gateway_ip }}" >> $GITHUB_STEP_SUMMARY
            echo "- **自訂 DNS**: ${{ inputs.dns_servers }}" >> $GITHUB_STEP_SUMMARY
          else
            echo "- **網路模式**: 🌐 標準主路由模式 (DHCP 啟用)" >> $GITHUB_STEP_SUMMARY
            echo "- **管理網址**: http://${{ inputs.lan_ip }}" >> $GITHUB_STEP_SUMMARY
          fi
          echo "- **預設帳號**: \`root\`" >> $GITHUB_STEP_SUMMARY
          echo "- **預設密碼**: \`無密碼（直接留空登入）\`" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "#### 📦 本次自訂集成軟體包" >> $GITHUB_STEP_SUMMARY
          echo "$PKGS_MD" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "#### 🔒 檔案 SHA256 校驗表" >> $GITHUB_STEP_SUMMARY
          echo '```text' >> $GITHUB_STEP_SUMMARY
          cat sha256sums.txt >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          
          echo "hashes<<EOF" >> $GITHUB_OUTPUT
          cat sha256sums.txt >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

          echo "pkgs_list<<EOF" >> $GITHUB_OUTPUT
          echo "$PKGS_MD" >> $GITHUB_OUTPUT
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
            - **網路模式**: ${{ inputs.is_bypass_router && '🛡️ 旁路由模式 (DHCP已關閉，NAT偽裝已開啟)' || '🌐 主路由模式' }}
            - **管理網址 (LAN IP)**: `http://${{ inputs.lan_ip }}`
            - **主路由網關 (Gateway)**: `${{ inputs.gateway_ip }}`
            - **自訂 DNS**: `${{ inputs.dns_servers }}`

            ### 🔑 預設登入認證資訊
            - **Web 管理網址**: `http://${{ inputs.lan_ip }}`
            - **使用者名稱 (User)**: `root`
            - **登入密碼 (Password)**: `無密碼（密碼欄留空，直接按登入即可）`

            ### 📦 本次自訂集成軟體包清單
            ${{ steps.summary.outputs.pkgs_list }}

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
    "name": "[友善] NanoPi R2S (雙千兆經典軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2s"
  },
  "nanopi_r2c": {
    "name": "[友善] NanoPi R2C (雙千兆軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c"
  },
  "nanopi_r4s": {
    "name": "[友善] NanoPi R4S (RK3399 高效軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s"
  },
  "nanopi_r4se": {
    "name": "[友善] NanoPi R4SE (內建 eMMC 高效軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4se"
  },
  "nanopi_r5s": {
    "name": "[友善] NanoPi R5S (三網口 雙 2.5G 軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5s"
  },
  "nanopi_r5c": {
    "name": "[友善] NanoPi R5C (雙 2.5G 迷你軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5c"
  },
  "nanopi_r6s": {
    "name": "[友善] NanoPi R6S (RK3588 雙 2.5G 旗艦軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6s"
  },
  "nanopi_r6c": {
    "name": "[友善] NanoPi R6C (RK3588 旗艦軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6c"
  },
  "rpi_4": {
    "name": "[樹莓派] Raspberry Pi 4 Model B / CM4",
    "target": "bcm27xx/bcm2711",
    "profile": "rpi-4"
  },
  "rpi_5": {
    "name": "[樹莓派] Raspberry Pi 5 (新一代高效單板電腦)",
    "target": "bcm27xx/bcm2712",
    "profile": "rpi-5"
  },
  "rpi_3": {
    "name": "[樹莓派] Raspberry Pi 3 Model B / B+",
    "target": "bcm27xx/bcm2710",
    "profile": "rpi-3"
  },
  "redmi_ax6000": {
    "name": "[紅米] Redmi AX6000 (MT7986 旗艦家用路由)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000"
  },
  "xiaomi_ax3000t": {
    "name": "[小米] 小米路由器 AX3000T (高 CP 值 Wi-Fi 6)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t"
  },
  "xiaomi_wr30u": {
    "name": "[小米] 小米路由器 WR30U (一般版 / 電信運營商版)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u"
  },
  "redmi_ax3200": {
    "name": "[紅米] Redmi AX3200 / 小米 AX6S",
    "target": "mediatek/mt7622",
    "profile": "xiaomi_redmi-router-ax3200"
  },
  "xiaomi_4a_gigabit": {
    "name": "[小米] 小米路由器 4A 千兆版 (MT7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit"
  },
  "glinet_mt3000": {
    "name": "[GL.iNet] GL-MT3000 (Beryl AX 便攜旅行路由)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt3000"
  },
  "glinet_mt6000": {
    "name": "[GL.iNet] GL-MT6000 (Flint 2 雙 2.5G 旗艦路由)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt6000"
  },
  "glinet_mt2500": {
    "name": "[GL.iNet] GL-MT2500 / MT2500A (Brume 2 雙網口網關)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt2500"
  },
  "glinet_axt1800": {
    "name": "[GL.iNet] GL-AXT1800 (Slate AX 三頻旅行路由)",
    "target": "ipq807x/generic",
    "profile": "glinet_gl-axt1800"
  },
  "glinet_ax1800": {
    "name": "[GL.iNet] GL-AX1800 (Flint 雙頻 Wi-Fi 6 路由)",
    "target": "ipq807x/generic",
    "profile": "glinet_gl-ax1800"
  },
  "asus_tuf_ax4200": {
    "name": "[華碩 ASUS] asus_tuf-ax4200 (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "asus_tuf-ax4200"
  },
  "tplink_xdr6088": {
    "name": "[TP-Link] TL-XDR6088 (雙 2.5G 旗艦 Wi-Fi 6)",
    "target": "mediatek/filogic",
    "profile": "tplink_tl-xdr6088"
  },
  "qihoo_360t7": {
    "name": "[360] qihoo_360t7 (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "qihoo_360t7"
  },
  "jcg_q30pro": {
    "name": "[捷稀] JCG Q30 Pro (MT7981 Wi-Fi 6)",
    "target": "mediatek/filogic",
    "profile": "jcg_q30-pro"
  },
  "phicomm_k2p": {
    "name": "[斐訊] Phicomm K2P (MT7621 經典千兆神機)",
    "target": "ramips/mt7621",
    "profile": "phicomm_k2p"
  },
  "asus_rt_ac3100": {
    "name": "[華碩 ASUS] asus_rt-ac3100 (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac3100"
  },
  "asus_rt_ac56u": {
    "name": "[華碩 ASUS] asus_rt-ac56u (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac56u"
  },
  "asus_rt_ac68u": {
    "name": "[華碩 ASUS] asus_rt-ac68u (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac68u"
  },
  "asus_rt_ac87u": {
    "name": "[華碩 ASUS] asus_rt-ac87u (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac87u"
  },
  "asus_rt_ac88u": {
    "name": "[華碩 ASUS] asus_rt-ac88u (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-ac88u"
  },
  "asus_rt_n18u": {
    "name": "[華碩 ASUS] asus_rt-n18u (bcm53xx/generic)",
    "target": "bcm53xx/generic",
    "profile": "asus_rt-n18u"
  },
  "xiaomi_redmi_router_ax6s": {
    "name": "[小米] xiaomi_redmi-router-ax6s (mediatek/mt7622)",
    "target": "mediatek/mt7622",
    "profile": "xiaomi_redmi-router-ax6s"
  },
  "asus_rt_ax59u": {
    "name": "[華碩 ASUS] asus_rt-ax59u (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "asus_rt-ax59u"
  },
  "asus_tuf_ax6000": {
    "name": "[華碩 ASUS] asus_tuf-ax6000 (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "asus_tuf-ax6000"
  },
  "glinet_gl_mt2500": {
    "name": "[GL.iNet] GL-MT2500 / MT2500A (Brume 2 雙網口網關)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt2500"
  },
  "glinet_gl_mt3000": {
    "name": "[GL.iNet] GL-MT3000 (Beryl AX 便攜旅行路由)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt3000"
  },
  "glinet_gl_mt6000": {
    "name": "[GL.iNet] GL-MT6000 (Flint 2 雙 2.5G 旗艦路由)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-mt6000"
  },
  "glinet_gl_x3000": {
    "name": "[GL.iNet] glinet_gl-x3000 (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-x3000"
  },
  "glinet_gl_xe3000": {
    "name": "[GL.iNet] glinet_gl-xe3000 (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "glinet_gl-xe3000"
  },
  "xiaomi_mi_router_ax3000t": {
    "name": "[小米] 小米路由器 AX3000T (高 CP 值 Wi-Fi 6)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t"
  },
  "xiaomi_mi_router_ax3000t_ubootmod": {
    "name": "[小米] xiaomi_mi-router-ax3000t-ubootmod (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-ax3000t-ubootmod"
  },
  "xiaomi_mi_router_wr30u_stock": {
    "name": "[小米] xiaomi_mi-router-wr30u-stock (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u-stock"
  },
  "xiaomi_mi_router_wr30u_ubootmod": {
    "name": "[小米] xiaomi_mi-router-wr30u-ubootmod (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_mi-router-wr30u-ubootmod"
  },
  "xiaomi_redmi_router_ax6000_stock": {
    "name": "[小米] xiaomi_redmi-router-ax6000-stock (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000-stock"
  },
  "xiaomi_redmi_router_ax6000_ubootmod": {
    "name": "[小米] xiaomi_redmi-router-ax6000-ubootmod (mediatek/filogic)",
    "target": "mediatek/filogic",
    "profile": "xiaomi_redmi-router-ax6000-ubootmod"
  },
  "asus_onhub": {
    "name": "[華碩 ASUS] asus_onhub (ipq806x/chromium)",
    "target": "ipq806x/chromium",
    "profile": "asus_onhub"
  },
  "xiaomi_mi_router_hd": {
    "name": "[小米] xiaomi_mi-router-hd (ipq806x/generic)",
    "target": "ipq806x/generic",
    "profile": "xiaomi_mi-router-hd"
  },
  "rpi_2": {
    "name": "[樹莓派] rpi-2 (bcm27xx/bcm2709)",
    "target": "bcm27xx/bcm2709",
    "profile": "rpi-2"
  },
  "rpi": {
    "name": "[樹莓派] rpi (bcm27xx/bcm2708)",
    "target": "bcm27xx/bcm2708",
    "profile": "rpi"
  },
  "friendlyarm_nanopc_t4": {
    "name": "[友善 NanoPi] friendlyarm_nanopc-t4 (rockchip/armv8)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopc-t4"
  },
  "friendlyarm_nanopc_t6": {
    "name": "[友善 NanoPi] friendlyarm_nanopc-t6 (rockchip/armv8)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopc-t6"
  },
  "friendlyarm_nanopi_r2c": {
    "name": "[友善] NanoPi R2C (雙千兆軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c"
  },
  "friendlyarm_nanopi_r2c_plus": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-r2c-plus (rockchip/armv8)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2c-plus"
  },
  "friendlyarm_nanopi_r2s": {
    "name": "[友善] NanoPi R2S (雙千兆經典軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r2s"
  },
  "friendlyarm_nanopi_r3s": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-r3s (rockchip/armv8)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r3s"
  },
  "friendlyarm_nanopi_r4s": {
    "name": "[友善] NanoPi R4S (RK3399 高效軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s"
  },
  "friendlyarm_nanopi_r4s_enterprise": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-r4s-enterprise (rockchip/armv8)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4s-enterprise"
  },
  "friendlyarm_nanopi_r4se": {
    "name": "[友善] NanoPi R4SE (內建 eMMC 高效軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r4se"
  },
  "friendlyarm_nanopi_r5c": {
    "name": "[友善] NanoPi R5C (雙 2.5G 迷你軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5c"
  },
  "friendlyarm_nanopi_r5s": {
    "name": "[友善] NanoPi R5S (三網口 雙 2.5G 軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r5s"
  },
  "friendlyarm_nanopi_r6c": {
    "name": "[友善] NanoPi R6C (RK3588 旗艦軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6c"
  },
  "friendlyarm_nanopi_r6s": {
    "name": "[友善] NanoPi R6S (RK3588 雙 2.5G 旗艦軟路由)",
    "target": "rockchip/armv8",
    "profile": "friendlyarm_nanopi-r6s"
  },
  "glinet_gl_mv1000": {
    "name": "[GL.iNet] glinet_gl-mv1000 (mvebu/cortexa53)",
    "target": "mvebu/cortexa53",
    "profile": "glinet_gl-mv1000"
  },
  "asus_rt_ax89x": {
    "name": "[Asus] asus_rt-ax89x (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "asus_rt-ax89x"
  },
  "redmi_ax6": {
    "name": "[紅米] redmi_ax6 (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "redmi_ax6"
  },
  "redmi_ax6_stock": {
    "name": "[紅米] redmi_ax6-stock (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "redmi_ax6-stock"
  },
  "xiaomi_ax3600": {
    "name": "[小米] xiaomi_ax3600 (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax3600"
  },
  "xiaomi_ax3600_stock": {
    "name": "[小米] xiaomi_ax3600-stock (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax3600-stock"
  },
  "xiaomi_ax9000": {
    "name": "[小米] xiaomi_ax9000 (qualcommax/ipq807x)",
    "target": "qualcommax/ipq807x",
    "profile": "xiaomi_ax9000"
  },
  "asus_rp_n53": {
    "name": "[華碩 ASUS] asus_rp-n53 (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "asus_rp-n53"
  },
  "asus_rt_ac51u": {
    "name": "[華碩 ASUS] asus_rt-ac51u (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "asus_rt-ac51u"
  },
  "asus_rt_ac54u": {
    "name": "[華碩 ASUS] asus_rt-ac54u (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "asus_rt-ac54u"
  },
  "asus_rt_n14u": {
    "name": "[華碩 ASUS] asus_rt-n14u (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "asus_rt-n14u"
  },
  "glinet_gl_mt300a": {
    "name": "[GL.iNet] glinet_gl-mt300a (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt300a"
  },
  "glinet_gl_mt300n": {
    "name": "[GL.iNet] glinet_gl-mt300n (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt300n"
  },
  "glinet_gl_mt750": {
    "name": "[GL.iNet] glinet_gl-mt750 (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "glinet_gl-mt750"
  },
  "xiaomi_miwifi_mini": {
    "name": "[小米] xiaomi_miwifi-mini (ramips/mt7620)",
    "target": "ramips/mt7620",
    "profile": "xiaomi_miwifi-mini"
  },
  "asus_rt_ac1200": {
    "name": "[華碩 ASUS] asus_rt-ac1200 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-ac1200"
  },
  "asus_rt_ac1200_v2": {
    "name": "[華碩 ASUS] asus_rt-ac1200-v2 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-ac1200-v2"
  },
  "asus_rt_n12_vp_b1": {
    "name": "[華碩 ASUS] asus_rt-n12-vp-b1 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "asus_rt-n12-vp-b1"
  },
  "glinet_gl_mt300n_v2": {
    "name": "[GL.iNet] glinet_gl-mt300n-v2 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "glinet_gl-mt300n-v2"
  },
  "glinet_microuter_n300": {
    "name": "[GL.iNet] glinet_microuter-n300 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "glinet_microuter-n300"
  },
  "glinet_vixmini": {
    "name": "[GL.iNet] glinet_vixmini (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "glinet_vixmini"
  },
  "xiaomi_mi_ra75": {
    "name": "[小米] xiaomi_mi-ra75 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-ra75"
  },
  "xiaomi_mi_router_4a_100m": {
    "name": "[小米] xiaomi_mi-router-4a-100m (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m"
  },
  "xiaomi_mi_router_4a_100m_intl": {
    "name": "[小米] xiaomi_mi-router-4a-100m-intl (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m-intl"
  },
  "xiaomi_mi_router_4a_100m_intl_v2": {
    "name": "[小米] xiaomi_mi-router-4a-100m-intl-v2 (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4a-100m-intl-v2"
  },
  "xiaomi_mi_router_4c": {
    "name": "[小米] xiaomi_mi-router-4c (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_mi-router-4c"
  },
  "xiaomi_miwifi_3c": {
    "name": "[小米] xiaomi_miwifi-3c (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_miwifi-3c"
  },
  "xiaomi_miwifi_nano": {
    "name": "[小米] xiaomi_miwifi-nano (ramips/mt76x8)",
    "target": "ramips/mt76x8",
    "profile": "xiaomi_miwifi-nano"
  },
  "asus_rp_ac56": {
    "name": "[華碩 ASUS] asus_rp-ac56 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rp-ac56"
  },
  "asus_rp_ac87": {
    "name": "[華碩 ASUS] asus_rp-ac87 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rp-ac87"
  },
  "asus_rt_ac57u_v1": {
    "name": "[華碩 ASUS] asus_rt-ac57u-v1 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac57u-v1"
  },
  "asus_rt_ac65p": {
    "name": "[華碩 ASUS] asus_rt-ac65p (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac65p"
  },
  "asus_rt_ac85p": {
    "name": "[華碩 ASUS] asus_rt-ac85p (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ac85p"
  },
  "asus_rt_ax53u": {
    "name": "[華碩 ASUS] asus_rt-ax53u (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ax53u"
  },
  "asus_rt_ax54": {
    "name": "[華碩 ASUS] asus_rt-ax54 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-ax54"
  },
  "asus_rt_n56u_b1": {
    "name": "[華碩 ASUS] asus_rt-n56u-b1 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "asus_rt-n56u-b1"
  },
  "glinet_gl_mt1300": {
    "name": "[GL.iNet] glinet_gl-mt1300 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "glinet_gl-mt1300"
  },
  "xiaomi_mi_router_3_pro": {
    "name": "[小米] xiaomi_mi-router-3-pro (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3-pro"
  },
  "xiaomi_mi_router_3g": {
    "name": "[小米] xiaomi_mi-router-3g (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3g"
  },
  "xiaomi_mi_router_3g_v2": {
    "name": "[小米] xiaomi_mi-router-3g-v2 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-3g-v2"
  },
  "xiaomi_mi_router_4": {
    "name": "[小米] xiaomi_mi-router-4 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4"
  },
  "xiaomi_mi_router_4a_gigabit": {
    "name": "[小米] 小米路由器 4A 千兆版 (MT7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit"
  },
  "xiaomi_mi_router_4a_gigabit_v2": {
    "name": "[小米] xiaomi_mi-router-4a-gigabit-v2 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-4a-gigabit-v2"
  },
  "xiaomi_mi_router_ac2100": {
    "name": "[小米] xiaomi_mi-router-ac2100 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-ac2100"
  },
  "xiaomi_mi_router_cr6606": {
    "name": "[小米] xiaomi_mi-router-cr6606 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6606"
  },
  "xiaomi_mi_router_cr6608": {
    "name": "[小米] xiaomi_mi-router-cr6608 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6608"
  },
  "xiaomi_mi_router_cr6609": {
    "name": "[小米] xiaomi_mi-router-cr6609 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_mi-router-cr6609"
  },
  "xiaomi_redmi_router_ac2100": {
    "name": "[小米] xiaomi_redmi-router-ac2100 (ramips/mt7621)",
    "target": "ramips/mt7621",
    "profile": "xiaomi_redmi-router-ac2100"
  },
  "asus_map_ac2200": {
    "name": "[華碩 ASUS] asus_map-ac2200 (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "asus_map-ac2200"
  },
  "asus_rt_ac42u": {
    "name": "[華碩 ASUS] asus_rt-ac42u (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "asus_rt-ac42u"
  },
  "asus_rt_ac58u": {
    "name": "[華碩 ASUS] asus_rt-ac58u (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "asus_rt-ac58u"
  },
  "glinet_gl_a1300": {
    "name": "[GL.iNet] glinet_gl-a1300 (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-a1300"
  },
  "glinet_gl_ap1300": {
    "name": "[GL.iNet] glinet_gl-ap1300 (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-ap1300"
  },
  "glinet_gl_b1300": {
    "name": "[GL.iNet] glinet_gl-b1300 (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-b1300"
  },
  "glinet_gl_b2200": {
    "name": "[GL.iNet] glinet_gl-b2200 (ipq40xx/generic)",
    "target": "ipq40xx/generic",
    "profile": "glinet_gl-b2200"
  },
  "friendlyarm_nanopi_neo_plus2": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-neo-plus2 (sunxi/cortexa53)",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-neo-plus2"
  },
  "friendlyarm_nanopi_neo2": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-neo2 (sunxi/cortexa53)",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-neo2"
  },
  "friendlyarm_nanopi_r1s_h5": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-r1s-h5 (sunxi/cortexa53)",
    "target": "sunxi/cortexa53",
    "profile": "friendlyarm_nanopi-r1s-h5"
  },
  "friendlyarm_nanopi_m1_plus": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-m1-plus (sunxi/cortexa7)",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-m1-plus"
  },
  "friendlyarm_nanopi_neo": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-neo (sunxi/cortexa7)",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-neo"
  },
  "friendlyarm_nanopi_neo_air": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-neo-air (sunxi/cortexa7)",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-neo-air"
  },
  "friendlyarm_nanopi_r1": {
    "name": "[友善 NanoPi] friendlyarm_nanopi-r1 (sunxi/cortexa7)",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_nanopi-r1"
  },
  "friendlyarm_zeropi": {
    "name": "[友善 NanoPi] friendlyarm_zeropi (sunxi/cortexa7)",
    "target": "sunxi/cortexa7",
    "profile": "friendlyarm_zeropi"
  },
  "glinet_gl_ar300m_nand": {
    "name": "[GL.iNet] glinet_gl-ar300m-nand (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar300m-nand"
  },
  "glinet_gl_ar300m_nor": {
    "name": "[GL.iNet] glinet_gl-ar300m-nor (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar300m-nor"
  },
  "glinet_gl_ar750s_nor": {
    "name": "[GL.iNet] glinet_gl-ar750s-nor (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar750s-nor"
  },
  "glinet_gl_ar750s_nor_nand": {
    "name": "[GL.iNet] glinet_gl-ar750s-nor-nand (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-ar750s-nor-nand"
  },
  "glinet_gl_e750": {
    "name": "[GL.iNet] glinet_gl-e750 (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-e750"
  },
  "glinet_gl_s200_nor": {
    "name": "[GL.iNet] glinet_gl-s200-nor (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-s200-nor"
  },
  "glinet_gl_s200_nor_nand": {
    "name": "[GL.iNet] glinet_gl-s200-nor-nand (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-s200-nor-nand"
  },
  "glinet_gl_x1200_nor": {
    "name": "[GL.iNet] glinet_gl-x1200-nor (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-x1200-nor"
  },
  "glinet_gl_x1200_nor_nand": {
    "name": "[GL.iNet] glinet_gl-x1200-nor-nand (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-x1200-nor-nand"
  },
  "glinet_gl_xe300": {
    "name": "[GL.iNet] glinet_gl-xe300 (ath79/nand)",
    "target": "ath79/nand",
    "profile": "glinet_gl-xe300"
  },
  "asus_pl_ac56": {
    "name": "[華碩 ASUS] asus_pl-ac56 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_pl-ac56"
  },
  "asus_rp_ac51": {
    "name": "[華碩 ASUS] asus_rp-ac51 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_rp-ac51"
  },
  "asus_rp_ac66": {
    "name": "[華碩 ASUS] asus_rp-ac66 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_rp-ac66"
  },
  "asus_rt_ac59u": {
    "name": "[華碩 ASUS] asus_rt-ac59u (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_rt-ac59u"
  },
  "asus_rt_ac59u_v2": {
    "name": "[華碩 ASUS] asus_rt-ac59u-v2 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_rt-ac59u-v2"
  },
  "asus_zenwifi_cd6n": {
    "name": "[華碩 ASUS] asus_zenwifi-cd6n (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_zenwifi-cd6n"
  },
  "asus_zenwifi_cd6r": {
    "name": "[華碩 ASUS] asus_zenwifi-cd6r (ath79/generic)",
    "target": "ath79/generic",
    "profile": "asus_zenwifi-cd6r"
  },
  "glinet_6408": {
    "name": "[GL.iNet] glinet_6408 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_6408"
  },
  "glinet_6416": {
    "name": "[GL.iNet] glinet_6416 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_6416"
  },
  "glinet_gl_ar150": {
    "name": "[GL.iNet] glinet_gl-ar150 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar150"
  },
  "glinet_gl_ar300m_lite": {
    "name": "[GL.iNet] glinet_gl-ar300m-lite (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar300m-lite"
  },
  "glinet_gl_ar300m16": {
    "name": "[GL.iNet] glinet_gl-ar300m16 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar300m16"
  },
  "glinet_gl_ar750": {
    "name": "[GL.iNet] glinet_gl-ar750 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-ar750"
  },
  "glinet_gl_mifi": {
    "name": "[GL.iNET] glinet_gl-mifi (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-mifi"
  },
  "glinet_gl_usb150": {
    "name": "[GL.iNET] glinet_gl-usb150 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-usb150"
  },
  "glinet_gl_x300b": {
    "name": "[GL.iNet] glinet_gl-x300b (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-x300b"
  },
  "glinet_gl_x750": {
    "name": "[GL.iNet] glinet_gl-x750 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "glinet_gl-x750"
  },
  "qihoo_c301": {
    "name": "[360] qihoo_c301 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "qihoo_c301"
  },
  "xiaomi_aiot_ac2350": {
    "name": "[小米] xiaomi_aiot-ac2350 (ath79/generic)",
    "target": "ath79/generic",
    "profile": "xiaomi_aiot-ac2350"
  },
  "xiaomi_mi_router_4q": {
    "name": "[小米] xiaomi_mi-router-4q (ath79/generic)",
    "target": "ath79/generic",
    "profile": "xiaomi_mi-router-4q"
  },
  "asus_rt_ac53u": {
    "name": "[華碩 ASUS] asus_rt-ac53u (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-ac53u"
  },
  "asus_rt_n14uhp": {
    "name": "[華碩 ASUS] asus_rt-n14uhp (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n14uhp"
  },
  "asus_rt_n15u": {
    "name": "[華碩 ASUS] asus_rt-n15u (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n15u"
  },
  "asus_rt_n16": {
    "name": "[華碩 ASUS] asus_rt-n16 (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n16"
  },
  "asus_rt_n66u": {
    "name": "[華碩 ASUS] asus_rt-n66u (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n66u"
  },
  "asus_rt_n66w": {
    "name": "[華碩 ASUS] asus_rt-n66w (bcm47xx/mips74k)",
    "target": "bcm47xx/mips74k",
    "profile": "asus_rt-n66w"
  },
  "asus_gt_ac5300": {
    "name": "[華碩 ASUS] asus_gt-ac5300 (bcm4908/generic)",
    "target": "bcm4908/generic",
    "profile": "asus_gt-ac5300"
  },
  "asus_rt_n56u": {
    "name": "[華碩 ASUS] asus_rt-n56u (ramips/rt3883)",
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

