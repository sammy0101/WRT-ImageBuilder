#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 旁路由引導模式 + OpenWrt 原版真·預裝 DAED (自帶 LuCI 選單與二進制)
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

# 6. 【真·預裝核心】DAED 二進制與 LuCI 選單完整提取注入
DAED_PREINSTALLED=false
mkdir -p packages

if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  echo ""
  echo "=========================================================="
  echo "  正在處理 OpenWrt 第三方外掛 (DAED & Argon)..."
  echo "=========================================================="

  # (A) 下載相容的 luci-theme-argon 放入 packages/
  if [[ " $PACKAGES_TO_BUILD " =~ " luci-theme-argon " ]]; then
    echo "下載 luci-theme-argon 安裝包..."
    if [ "$is_apk" = true ]; then
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon-2.4.7-r1.apk"
    else
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7-1_all.ipk"
    fi
    wget -q -c --timeout=20 --tries=3 "$ARGON_URL" -P packages/ || true
  fi

  # (B) daed 與 luci-app-daed：下載並使用官方 host apk 解壓進 files/
  if [[ " $PACKAGES_TO_BUILD " =~ " daed " ]]; then
    echo "下載 DAED 核心與 LuCI 介面包..."
    mkdir -p /tmp/daed_dl files/usr/bin files/etc/init.d files/etc/daed

    if [ "$is_apk" = true ]; then
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed-2026.07.31-r1-x86_64-openwrt-25.12.apk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed-1.4-r1-openwrt-25.12.apk"
    else
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed_2026.07.31-r1_x86_64-openwrt-24.10.ipk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed_1.4-r1_all-openwrt-24.10.ipk"
    fi

    # 使用 curl -fL 確保 404 時不會寫入錯誤網頁
    curl -fL -sS --connect-timeout 20 --retry 3 "$DAED_BIN_URL" -o /tmp/daed_dl/daed_core.pkg || echo "⚠️ 下載 DAED 核心失敗"
    curl -fL -sS --connect-timeout 20 --retry 3 "$DAED_LUCI_URL" -o /tmp/daed_dl/daed_luci.pkg || echo "⚠️ 下載 DAED LuCI 失敗"

    echo "正在提取安裝包並直接注入固件檔案系統..."
    for p_file in /tmp/daed_dl/*.pkg; do
      [ -s "$p_file" ] || continue
      echo "正在提取組件: $(basename "$p_file")..."
      
      # 方案 1: 使用 ImageBuilder 自帶的 host apk 工具官方提取 (針對 25.12)
      if [ "$is_apk" = true ] && [ -x "staging_dir/host/bin/apk" ]; then
        ./staging_dir/host/bin/apk extract --allow-untrusted --destination "$PWD/files/" "$p_file" 2>/dev/null || true
      fi
      
      # 方案 2: 使用 7z 萬能解包輔助
      if command -v 7z >/dev/null 2>&1; then
        mkdir -p /tmp/pkg_7z
        7z x -y "$p_file" -o/tmp/pkg_7z/ >/dev/null 2>&1 || true
        if [ -f "/tmp/pkg_7z/data.tar.gz" ]; then
          tar -xzf /tmp/pkg_7z/data.tar.gz -C "$PWD/files/" 2>/dev/null || true
        fi
        cp -rf /tmp/pkg_7z/* "$PWD/files/" 2>/dev/null || true
        rm -rf /tmp/pkg_7z
      fi
      
      # 方案 3: 針對 24.10 ipk 的標準解壓
      if tar -tf "$p_file" 2>/dev/null | grep -q "data.tar.gz"; then
        tar -xzf "$p_file" data.tar.gz -O 2>/dev/null | tar -xzf - -C "$PWD/files/" 2>/dev/null || true
      fi
    done

    rm -rf files/.PKGINFO files/.SIGN.* files/control.tar.gz files/data.tar.gz files/debian-binary /tmp/daed_dl 2>/dev/null || true

    # 確保標準 init.d 服務腳本存在
    if [ ! -f "files/etc/init.d/daed" ]; then
      cat <<'INITSCRIPT' > files/etc/init.d/daed
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

PROG=/usr/bin/daed
CONF_DIR=/etc/daed
LOG_DIR=/var/log/daed

start_service() {
    [ -x "$PROG" ] || return 1
    mkdir -p "$CONF_DIR" "$LOG_DIR"
    procd_open_instance
    procd_set_param command "$PROG" run -c "$CONF_DIR" -l "$LOG_DIR"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall daed 2>/dev/null || true
}
INITSCRIPT
    fi

    chmod +x files/usr/bin/daed files/etc/init.d/daed 2>/dev/null || true

    # 驗證二進制與 LuCI 選單實體
    if [ -f "files/usr/bin/daed" ]; then
      echo "✓ DAED 二進制核心注入成功: /usr/bin/daed ($(ls -lh files/usr/bin/daed | awk '{print $5}'))"
      DAED_PREINSTALLED=true
    fi

    if [ -f "files/usr/share/luci/menu.d/luci-app-daed.json" ] || [ -f "files/usr/lib/lua/luci/controller/daed.lua" ]; then
      echo "✓ DAED LuCI 網頁選單注入成功！"
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
