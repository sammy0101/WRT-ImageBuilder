#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 honk / dae 本地倉庫實體下載與自動簽名 + 旁路由模式 + VMware .vmdk
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-25.12.6}"
SELECTED_DEVICE="${DEVICE_MODEL:-x86_generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
USE_OFFICIAL="${USE_OFFICIAL_REPO:-false}"
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
echo "  開始構建雲端自訂韌體"
echo "  系統類型: $FW_TYPE"
echo "  系統版本: $FW_VER"
echo "  所選設備: $DEVICE_KEY"
echo "  目標架構 (Target): $TARGET_INPUT"
echo "  設備代號 (Profile): $PROFILE_NAME"
echo "  官方原廠源: $([ "$USE_OFFICIAL" = "true" ] && echo "啟用" || echo "停用")"
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
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-i18n-opkg-zh-tw//g; s/luci-app-opkg//g; s/luci-app-argon-config//g')
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
ENABLE_ISTOREOS_HOME="false"
EOF

if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 【daeuniverse 官方套件實體下載至 packages/ 解決 UNTRUSTED 報錯】
mkdir -p packages

if [[ " $PACKAGES_TO_BUILD " =~ " honk " ]] || [[ " $PACKAGES_TO_BUILD " =~ " dae " ]]; then
  echo ""
  echo "=========================================================="
  echo "  正在從 daeuniverse 官方抓取真實安裝包至本地 packages/ 倉庫..."
  echo "=========================================================="

  # 下載官方簽名公鑰給開機後使用
  wget -q -c --timeout=20 --tries=3 "https://openwrt.daeuniverse.org/public-key.pem" -O files/etc/apk/keys/daeuniverse.pem || true

  # 寫入開機後的 apk 來源清單 (讓路由器以後在線上也能更新)
  FEED_BASE="https://openwrt.daeuniverse.org/25.12"
  cat <<DAE_REPO > files/etc/apk/repositories.d/daeuniverse.list
@daeuniverse ${FEED_BASE}/packages/x86_64/packages.adb
DAE_REPO
  if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
    echo "@daeuniverse ${FEED_BASE}/kmods/${FW_VER}/${TARGET_DIR}/${SUBTARGET_DIR}/packages.adb" >> files/etc/apk/repositories.d/daeuniverse.list
  fi

  # 直接從官方 Release 抓取編譯好的 APK 檔案放入 packages/ 目錄
  # 這樣 ImageBuilder 會自動以本地生成的金鑰完成信任簽名，完全避免 UNTRUSTED 報錯
  RELEASE_API_URL="https://api.github.com/repos/daeuniverse/openwrt-packages/releases/latest"
  RELEASE_JSON=$(curl -sL --connect-timeout 15 "$RELEASE_API_URL" 2>/dev/null || true)

  # 下載 honk 與 luci-app-honk
  if [[ " $PACKAGES_TO_BUILD " =~ " honk " ]]; then
    echo "下載 honk 官方套件..."
    HONK_URLS=$(echo "$RELEASE_JSON" | grep -oE 'https://github.com/daeuniverse/openwrt-packages/releases/download/[^"]*(honk|vmlinux)[^"]*\.apk' | sort -u || true)
    
    # 備用直鏈 (若 API 受限)
    if [ -z "$HONK_URLS" ]; then
      HONK_BASE="https://github.com/daeuniverse/openwrt-packages/releases/download/openwrt-25.12.6-6.12.112-20261024"
      HONK_URLS="${HONK_BASE}/honk-0.0.1-r1.apk ${HONK_BASE}/luci-app-honk-0.0.1-r1.apk ${HONK_BASE}/vmlinux-6.12.112-x86_64.apk"
    fi

    for url in $HONK_URLS; do
      echo "下載: $(basename "$url")..."
      wget -q -c --timeout=25 --tries=3 "$url" -P packages/ || true
    done
  fi

  # 下載 dae 與 luci-app-dae
  if [[ " $PACKAGES_TO_BUILD " =~ " dae " ]]; then
    echo "下載 dae 官方套件..."
    DAE_URLS=$(echo "$RELEASE_JSON" | grep -oE 'https://github.com/daeuniverse/openwrt-packages/releases/download/[^"]*(dae-|luci-app-dae|vmlinux)[^"]*\.apk' | sort -u || true)
    
    if [ -z "$DAE_URLS" ]; then
      DAE_BASE="https://github.com/daeuniverse/openwrt-packages/releases/download/openwrt-25.12.6-6.12.112-20261024"
      DAE_URLS="${DAE_BASE}/dae-0.8.0-r1.apk ${DAE_BASE}/luci-app-dae-0.8.0-r1.apk ${DAE_BASE}/vmlinux-6.12.112-x86_64.apk"
    fi

    for url in $DAE_URLS; do
      echo "下載: $(basename "$url")..."
      wget -q -c --timeout=25 --tries=3 "$url" -P packages/ || true
    done
  fi

  echo "✓ 本地 packages/ 倉庫檔案清單:"
  ls -lh packages/ || true
  echo "=========================================================="
  echo ""
fi

# 7. 第三方套件處理 (Argon 主題)
if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  if [[ " $PACKAGES_TO_BUILD " =~ " luci-theme-argon " ]]; then
    echo "正在下載相容的 luci-theme-argon..."
    if [ "$is_apk" = true ]; then
      ARGON_THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon-2.4.7-r1.apk"
    else
      ARGON_THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7-1_all.ipk"
    fi
    wget -q -c --timeout=20 --tries=3 "$ARGON_THEME_URL" -P packages/ || true
  fi

  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-app-turboacc//g')
fi

# 8. 清洗官方原廠源 (若開啟)
if [ "$USE_OFFICIAL" = "true" ]; then
  echo "正在將 ImageBuilder 編譯環境替換為官方源..."
  for repo_cfg in "repositories" "repositories.conf"; do
    if [ -f "$repo_cfg" ]; then
      if [[ "${FW_TYPE,,}" == "immortalwrt" ]]; then
        sed -i 's|mirrors.vsean.net/openwrt|downloads.immortalwrt.org|g' "$repo_cfg"
        sed -i 's|https://.*/releases/|https://downloads.immortalwrt.org/releases/|g' "$repo_cfg"
        sed -i 's|http://.*/releases/|https://downloads.immortalwrt.org/releases/|g' "$repo_cfg"
      else
        sed -i 's|https://.*/releases/|https://downloads.openwrt.org/releases/|g' "$repo_cfg"
        sed -i 's|http://.*/releases/|https://downloads.openwrt.org/releases/|g' "$repo_cfg"
      fi
    fi
  done
fi

PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | xargs)
echo "最終交給套件管理器的軟體包列表: $PACKAGES_TO_BUILD"

# 9. 打包構建 (帶有容錯自癒)
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

  local missing_pkgs=$(grep -E '^\s+[a-zA-Z0-9_\.\-\@]+ \(no such package\):' "$log_tmp" | awk '{print $1}' | tr '\n' ' ')
  local tag_missing=$(grep -oE "dependency '[^']+'" "$log_tmp" | cut -d"'" -f2 | tr '\n' ' ')
  local parent_raw=$(grep -oE '[a-zA-Z0-9_\.\-\@]+\[[^]]+\]' "$log_tmp" | cut -d'[' -f1 | grep -v '^world$' | tr '\n' ' ')
  local parent_clean=""
  for p in $parent_raw; do
    c_name=$(echo "$p" | sed -E 's/-[0-9].*//; s/_[0-9].*//')
    parent_clean="$parent_clean $c_name"
  done

  local missing_opkg=$(grep -oE "Unknown package '[^']+'" "$log_tmp" | cut -d"'" -f2 | tr '\n' ' ')
  local missing_opkg2=$(grep -oE "Cannot install package [^.]+" "$log_tmp" | awk '{print $NF}' | tr '\n' ' ')

  local all_culprits=$(echo "$missing_pkgs $tag_missing $parent_clean $missing_opkg $missing_opkg2" | xargs -n1 2>/dev/null | sed -E 's/@[a-zA-Z0-9_-]+//g' | grep -v '^make$' | sort -u | xargs 2>/dev/null || echo "")

  if [ -n "$all_culprits" ]; then
    echo "⚠️ 剔除不可用套件: $all_culprits 並重試..."
    local cleaned_pkgs="$current_pkgs"
    for item in $all_culprits; do
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )$item(@[a-zA-Z0-9_-]+)?( |\$)/ /g")
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

# 10. 自動轉換 VMware .vmdk 虛擬磁碟格式
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
