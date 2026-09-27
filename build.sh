#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 旁路由引導模式 + OpenWrt 原版預裝 DAED + 官方原裝英文 + VMware .vmdk
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
GW_IP="${GATEWAY_IP:-192.168.100.1}"
DNS_IPS="${DNS_SERVERS:-192.168.100.1 8.8.8.8}"
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
if ! wget -q -c "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"; then
  ARCHIVE_NAME="${ARCHIVE_NAME%.zst}.xz"
  echo "嘗試 .tar.xz 備用格式: $BASE_URL/$ARCHIVE_NAME"
  wget -c "$BASE_URL/$ARCHIVE_NAME" -O "$WORKDIR/$ARCHIVE_NAME"
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

# 寫入旁路由與網路參數設定檔
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
    wget -q -c "$ARGON_URL" -P packages/ || true
  fi

  # (B) daed 與 luci-app-daed 實體檔案解壓注入
  if [[ " $PACKAGES_TO_BUILD " =~ " daed " ]]; then
    echo "下載 daed 二進制核心與管理介面..."
    mkdir -p /tmp/daed_dl /tmp/daed_ext files/usr/bin files/etc/init.d files/etc/daed

    if [ "$is_apk" = true ]; then
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed-2026.07.31-r1-x86_64-openwrt-25.12.apk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed-1.4-r1-openwrt-25.12.apk"
    else
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed_2026.07.31-r1_x86_64-openwrt-24.10.ipk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed_1.4-r1_all-openwrt-24.10.ipk"
    fi

    wget -q -c "$DAED_BIN_URL" -O /tmp/daed_dl/daed.apk || true
    wget -q -c "$DAED_LUCI_URL" -O /tmp/daed_dl/luci.apk || true

    # 使用 Python 提取 apk 內所有流段
    python3 - <<'EOF'
import os, gzip, tarfile, io

dl_dir = "/tmp/daed_dl"
out_dir = "/tmp/daed_ext"
os.makedirs(out_dir, exist_ok=True)

for fname in os.listdir(dl_dir):
    fpath = os.path.join(dl_dir, fname)
    if not os.path.isfile(fpath):
        continue
    try:
        with open(fpath, "rb") as f:
            data = f.read()
        offset = 0
        while offset < len(data):
            idx = data.find(b"\x1f\x8b", offset)
            if idx == -1:
                break
            try:
                decomp = gzip.decompress(data[idx:])
                with tarfile.open(fileobj=io.BytesIO(decomp)) as tar:
                    tar.extractall(path=out_dir)
                offset = idx + 10
            except Exception:
                offset += 2
    except Exception as e:
        print(f"Error extracting {fname}: {e}")
EOF

    cp -rf /tmp/daed_ext/* files/ 2>/dev/null || true
    rm -rf /tmp/daed_dl /tmp/daed_ext

    # 備用獨立版二進制兜底
    if [ ! -f "files/usr/bin/daed" ]; then
      echo "正在下載官方獨立版 daed 二進制檔案兜底..."
      wget -q -c "https://github.com/daeuniverse/daed/releases/download/v0.8.0/daed-linux-x86_64.tar.gz" -O /tmp/daed.tar.gz || true
      if [ -f "/tmp/daed.tar.gz" ]; then
        tar -xzf /tmp/daed.tar.gz -C /tmp/ 2>/dev/null || true
        mv /tmp/daed-linux-x86_64 files/usr/bin/daed 2>/dev/null || true
        rm -f /tmp/daed.tar.gz
      fi
    fi

    # 建立官方標準 init.d 啟動服務腳本
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

    chmod +x files/usr/bin/daed 2>/dev/null || true
    chmod +x files/etc/init.d/daed 2>/dev/null || true

    if [ -f "files/usr/bin/daed" ]; then
      echo "✓ DAED 二進制注入成功: /usr/bin/daed (大小: $(ls -lh files/usr/bin/daed | awk '{print $5}'))"
      DAED_PREINSTALLED=true
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
