#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 honk / dae 本地倉庫注入 + Argon雙件套 + iStoreOS首頁 + VMware .vmdk
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-25.12.5}"
SELECTED_DEVICE="${DEVICE_MODEL:-x86_generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
USE_OFFICIAL="${USE_OFFICIAL_REPO:-false}"
ENABLE_ISTORE_HOME="${ENABLE_ISTOREOS_DASHBOARD:-false}"
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
echo "  iStoreOS 首頁: $([ "$ENABLE_ISTORE_HOME" = "true" ] && echo "🎨 啟用 (QuickStart 拓撲儀表板)" || echo "預設首頁")"
echo "  官方原廠源: $([ "$USE_OFFICIAL" = "true" ] && echo "啟用 (downloads 官方源)" || echo "停用 (維持預設)")"
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

# 整合 iStoreOS 經典首頁組件 (QuickStart)
if [[ "$ENABLE_ISTORE_HOME" == "true" ]]; then
  echo "✓ 已勾選啟用 iStoreOS 經典首頁 (QuickStart 網絡拓撲與狀態儀表板)"
  PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD quickstart luci-app-quickstart"
fi

is_apk=false
if [[ "$FW_VER" =~ ^25\. ]] || [ -f "staging_dir/host/bin/apk" ]; then
  is_apk=true
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-i18n-opkg-zh-tw//g; s/luci-app-opkg//g')
fi

# 5. 整合 Overlay 檔案 (files 系統覆蓋層)
mkdir -p files/etc/uci-defaults files/etc/config files/etc/apk/keys files/etc/apk/repositories.d
cp -r "$ROOT_DIR/files/"* files/

cat <<EOF > files/etc/custom_network_config
CUSTOM_LAN_IP="$TARGET_IP"
IS_BYPASS_ROUTER="$IS_BYPASS"
GATEWAY_IP="$GW_IP"
DNS_SERVERS="$DNS_IPS"
USE_OFFICIAL_REPO="$USE_OFFICIAL"
FW_SYSTEM_TYPE="$FW_TYPE"
ENABLE_ISTOREOS_HOME="$ENABLE_ISTORE_HOME"
EOF

if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 【第三方外部套件下載至 packages/ 本地倉庫】
mkdir -p packages

# (A) 下載 daeuniverse 官方 honk / dae (若有勾選)
if [[ " $PACKAGES_TO_BUILD " =~ " honk " ]] || [[ " $PACKAGES_TO_BUILD " =~ " dae " ]]; then
  echo ""
  echo "=========================================================="
  echo "  正在從官方發布源抓取 honk / dae 套件至本地倉庫..."
  echo "=========================================================="

  # 下載官方簽名公鑰備查
  wget -q -c --timeout=20 --tries=3 "https://openwrt.daeuniverse.org/public-key.pem" -O files/etc/apk/keys/daeuniverse.pem || true

  # 抓取 25.12 x86_64 官方最新 releases 包
  DAE_RELEASE_TAG="openwrt-25.12.6-6.12.112-20261024"
  DAE_BASE="https://github.com/daeuniverse/openwrt-packages/releases/download/${DAE_RELEASE_TAG}"

  if [[ " $PACKAGES_TO_BUILD " =~ " honk " ]]; then
    echo "下載 honk 與 luci-app-honk..."
    wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/honk-0.0.1-r1.apk" -P packages/ || true
    wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/luci-app-honk-0.0.1-r1.apk" -P packages/ || true
    wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/luci-i18n-daeuniverse-zh-tw-0.0.1-r1.apk" -P packages/ || true
    # 若為 OpenWrt 官方原版，補齊 matching vmlinux-btf
    if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
      wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/vmlinux-6.12.112-x86_64.apk" -P packages/ || true
    fi
  fi

  if [[ " $PACKAGES_TO_BUILD " =~ " dae " ]]; then
    echo "下載 dae 與 luci-app-dae..."
    wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/dae-0.8.0-r1.apk" -P packages/ || true
    wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/luci-app-dae-0.8.0-r1.apk" -P packages/ || true
    if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
      wget -q -c --timeout=20 --tries=3 "${DAE_BASE}/vmlinux-6.12.112-x86_64.apk" -P packages/ || true
    fi
  fi
  echo "=========================================================="
  echo ""
fi

# (B) 下載相容的 luci-theme-argon 與 luci-app-argon-config
if [[ " $PACKAGES_TO_BUILD " =~ " luci-theme-argon " ]]; then
  echo "正在下載相容的 luci-theme-argon..."
  if [ "$is_apk" = true ]; then
    ARGON_THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon-2.4.7-r1.apk"
  else
    ARGON_THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7-1_all.ipk"
  fi
  wget -q -c --timeout=20 --tries=3 "$ARGON_THEME_URL" -P packages/ || true
fi

if [[ " $PACKAGES_TO_BUILD " =~ " luci-app-argon-config " ]]; then
  echo "正在下載相容的 luci-app-argon-config..."
  if [ "$is_apk" = true ]; then
    ARGON_CONFIG_URL="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config-0.9-r1.apk"
  else
    ARGON_CONFIG_URL="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk"
  fi
  wget -q -c --timeout=20 --tries=3 "$ARGON_CONFIG_URL" -P packages/ || true
fi

# 7. 清洗官方原廠源 (若開啟)
if [ "$USE_OFFICIAL" = "true" ] && [ -f "repositories.conf" ]; then
  echo "正在將 ImageBuilder 編譯環境替換為官方源..."
  if [[ "${FW_TYPE,,}" == "immortalwrt" ]]; then
    sed -i 's|mirrors.vsean.net/openwrt|downloads.immortalwrt.org|g' repositories.conf
    sed -i 's|https://.*/releases/|https://downloads.immortalwrt.org/releases/|g' repositories.conf
    sed -i 's|http://.*/releases/|https://downloads.immortalwrt.org/releases/|g' repositories.conf
  else
    sed -i 's|https://.*/releases/|https://downloads.openwrt.org/releases/|g' repositories.conf
    sed -i 's|http://.*/releases/|https://downloads.openwrt.org/releases/|g' repositories.conf
  fi
fi

if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-app-turboacc//g')
fi

PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | xargs)
echo "最終交給套件管理器的軟體包列表: $PACKAGES_TO_BUILD"

# 8. 打包構建 (帶有容錯自癒)
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
    
    echo "$current_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' > "$OUTPUT_DIR/custom_packages.txt"
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
      rm -f packages/*"$item"* 2>/dev/null || true
    done
    cleaned_pkgs=$(echo "$cleaned_pkgs" | xargs)

    if make image \
      PROFILE="$PROFILE_NAME" \
      PACKAGES="$cleaned_pkgs" \
      FILES="files" \
      ROOTFS_PARTSIZE="$PARTSIZE_MB" \
      BIN_DIR="$OUTPUT_DIR"; then
      echo "$cleaned_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' > "$OUTPUT_DIR/custom_packages.txt"
      return 0
    fi
    return 1
  fi

  return 1
}

execute_make_image "$PACKAGES_TO_BUILD"

# 9. 自動轉換 VMware .vmdk 虛擬磁碟格式
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
