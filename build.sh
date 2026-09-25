#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 OpenWrt 與 ImmortalWrt, 處理 GB 轉 MB, 自動拉取 ImageBuilder 並構建
# ==============================================================================
set -euo pipefail

# 1. 讀取並標準化參數
FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-24.10.0}"
TARGET_INPUT="${TARGET_ARCH:-x86/64}"
PROFILE_NAME="${PROFILE:-generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
TARGET_IP="${LAN_IP:-192.168.100.1}"
PPPOE_EN="${ENABLE_PPPOE:-false}"

echo "=========================================================="
echo "  開始構建雲端自訂韌體"
echo "  系統類型: $FW_TYPE"
echo "  系統版本: $FW_VER"
echo "  目標架構: $TARGET_INPUT"
echo "  設備型號: $PROFILE_NAME"
echo "  設定容量: $SIZE_IN_GB GB"
echo "=========================================================="

# 2. 驗證分區大小並將 GB 換算為 MB (1 GB = 1024 MB)
if ! [[ "$SIZE_IN_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "錯誤: 輸入的空間大小必須為數字！當前值: '$SIZE_IN_GB'" >&2
  exit 1
fi
PARTSIZE_MB=$(awk -v gb="$SIZE_IN_GB" 'BEGIN { printf "%.0f", gb * 1024 }')
echo "✓ 軟體包分區已轉換: ${SIZE_IN_GB} GB -> ${PARTSIZE_MB} MB"

# 3. 解析 Target 與 Subtarget (例: x86/64 -> TARGET=x86, SUBTARGET=64)
IFS='/' read -r TARGET_DIR SUBTARGET_DIR <<< "$TARGET_INPUT"

# 4. 判斷下載路徑
DOWNLOAD_NAME=""
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
  # 降級嘗試 .tar.xz (舊版本常用壓縮格式)
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

# 注入自訂 LAN IP 變數
echo "CUSTOM_LAN_IP=\"$TARGET_IP\"" > files/etc/custom_lan_ip

# 注入 PPPoE 設定
if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 整合自訂軟體包清單
source "$PWD/../../shell/custom-packages.sh"
PACKAGES_TO_BUILD="$CUSTOM_PACKAGES"

# 處理 Docker 支援
if [[ "$DOCKER_FLAG" == "true" ]]; then
  echo "✓ 已勾選整合 Docker 與 Dockerman 管理套件"
  PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-tw"
fi

echo "最終包含軟體包列表:"
echo "$PACKAGES_TO_BUILD"

# 7. 開始進行 ImageBuilder 打包
echo "開始編譯產生固件映像檔..."
make image \
  PROFILE="$PROFILE_NAME" \
  PACKAGES="$PACKAGES_TO_BUILD" \
  FILES="files" \
  ROOTFS_PARTSIZE="$PARTSIZE_MB" \
  BIN_DIR="$OUTPUT_DIR"

echo "✓ 韌體已生成於: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
