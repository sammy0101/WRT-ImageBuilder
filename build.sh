#!/usr/bin/env bash
# ==============================================================================
# 核心構建程式: build.sh
# 支援 OpenWrt 原版真·二進制直植入 daed + 強制自訂 IP + 自動轉換 VMware .vmdk
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FW_TYPE="${FIRMWARE_TYPE:-ImmortalWrt}"
FW_VER="${VERSION:-25.12.5}"
SELECTED_DEVICE="${DEVICE_MODEL:-x86_generic}"
SIZE_IN_GB="${ROOTFS_SIZE_G:-1}"
DOCKER_FLAG="${INCLUDE_DOCKER:-false}"
TARGET_IP="${LAN_IP:-192.168.100.1}"
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
echo "  所選設備鍵名: $DEVICE_KEY"
echo "  目標架構 (Target): $TARGET_INPUT"
echo "  設備代號 (Profile): $PROFILE_NAME"
echo "  自訂 LAN IP: $TARGET_IP"
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
  PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-tw"
fi

is_apk=false
if [[ "$FW_VER" =~ ^25\. ]] || [ -f "staging_dir/host/bin/apk" ]; then
  is_apk=true
  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-i18n-opkg-zh-tw//g; s/luci-app-opkg//g')
fi

# 5. 整合 Overlay 檔案 (files 系統覆蓋層)
mkdir -p files/etc/uci-defaults files/etc/config
cp -r "$ROOT_DIR/files/"* files/

echo "CUSTOM_LAN_IP=\"$TARGET_IP\"" > files/etc/custom_lan_ip

if [[ "$PPPOE_EN" == "true" ]]; then
  cat <<EOF > files/etc/config/pppoe-settings
ENABLE_PPPOE="yes"
PPPOE_ACCOUNT="${PPPOE_ACCOUNT:-}"
PPPOE_PASSWORD="${PPPOE_PASSWORD:-}"
EOF
fi

# 6. 【真·二進制多流解壓】OpenWrt 專屬：daed 完整實體注入 files/
DAED_PREINSTALLED=false
mkdir -p packages

if [[ "${FW_TYPE,,}" == "openwrt" ]]; then
  echo ""
  echo "=========================================================="
  echo "  偵測到 OpenWrt 原版系統：執行外部外掛直植入程序..."
  echo "=========================================================="

  # (A) luci-theme-argon 本地倉庫下載
  if [[ " $PACKAGES_TO_BUILD " =~ " luci-theme-argon " ]]; then
    echo "正在下載相容的 luci-theme-argon..."
    if [ "$is_apk" = true ]; then
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon-2.4.7-r1.apk"
    else
      ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7/luci-theme-argon_2.4.7-1_all.ipk"
    fi
    wget -q -c "$ARGON_URL" -P packages/ || true
  fi

  # (B) daed 與 luci-app-daed：多流解壓縮直接釋放進 files/
  if [[ " $PACKAGES_TO_BUILD " =~ " daed " ]]; then
    echo "正在下載 daed 與 LuCI 面板..."
    if [ "$is_apk" = true ]; then
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed-2026.07.31-r1-x86_64-openwrt-25.12.apk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed-1.4-r1-openwrt-25.12.apk"
    else
      DAED_BIN_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/daed_2026.07.31-r1_x86_64-openwrt-24.10.ipk"
      DAED_LUCI_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/daed_2026.07.31-r1/luci-app-daed_1.4-r1_all-openwrt-24.10.ipk"
    fi

    mkdir -p /tmp/daed_download /tmp/daed_extract
    wget -q -c "$DAED_BIN_URL" -O /tmp/daed_download/daed.pkg || true
    wget -q -c "$DAED_LUCI_URL" -O /tmp/daed_download/luci-daed.pkg || true

    # 使用 python/tarfile 完整提取 apk/ipk 內所有串聯 gzip 區塊 (包含真實資料流)
    python3 - <<'EOF'
import os, gzip, tarfile

dl_dir = "/tmp/daed_download"
out_dir = "/tmp/daed_extract"

for fname in os.listdir(dl_dir):
    fpath = os.path.join(dl_dir, fname)
    if not os.path.isfile(fpath):
        continue
    try:
        # 解開多段串聯的 gzip tar 流
        with open(fpath, "rb") as f:
            data = f.read()
        
        offset = 0
        while offset < len(data):
            try:
                # 尋找 gzip 魔數 (0x1f, 0x8b)
                idx = data.find(b"\x1f\x8b", offset)
                if idx == -1:
                    break
                decompressed = gzip.decompress(data[idx:])
                # 將解開的 tar 提取到目標目錄
                import io
                with tarfile.open(fileobj=io.BytesIO(decompressed)) as tar:
                    tar.extractall(path=out_dir)
                offset = idx + 10 # 推進游標繼續掃描後續區塊
            except Exception:
                offset += 2
    except Exception as e:
        print(f"提取 {fname} 錯誤: {e}")
EOF

    # 檢查是否包含嵌套的 data.tar.gz (常見於 ipk)
    if [ -f "/tmp/daed_extract/data.tar.gz" ]; then
      tar -xzf /tmp/daed_extract/data.tar.gz -C /tmp/daed_extract/ 2>/dev/null || true
      rm -f /tmp/daed_extract/data.tar.gz /tmp/daed_extract/control.tar.gz 2>/dev/null || true
    fi

    # 清除套件元數據
    rm -rf /tmp/daed_extract/.PKGINFO /tmp/daed_extract/.SIGN.* 2>/dev/null || true

    # 將提取到的真實二進制檔複製覆蓋進 files/ 韌體檔案系統
    cp -rf /tmp/daed_extract/* files/ 2>/dev/null || true
    rm -rf /tmp/daed_download /tmp/daed_extract

    chmod +x files/usr/bin/daed 2>/dev/null || true
    chmod +x files/etc/init.d/daed 2>/dev/null || true

    # 驗證二進制檔是否真的植入成功
    if [ -f "files/usr/bin/daed" ]; then
      echo "✓ 驗證成功: /usr/bin/daed 實體檔案已成功寫入固件！大小: $(ls -lh files/usr/bin/daed | awk '{print $5}')"
      DAED_PREINSTALLED=true
    else
      echo "⚠️ 警告: 未能在 files/usr/bin/daed 找到實體檔案，嘗試備用下載..."
      mkdir -p files/usr/bin files/etc/init.d
      wget -q -c "https://github.com/daeuniverse/daed/releases/download/v0.8.0/daed-linux-x86_64.tar.gz" -O /tmp/daed_standalone.tar.gz || true
      if [ -f "/tmp/daed_standalone.tar.gz" ]; then
        tar -xzf /tmp/daed_standalone.tar.gz -C files/usr/bin/ 2>/dev/null || true
        mv files/usr/bin/daed-linux-x86_64 files/usr/bin/daed 2>/dev/null || true
        chmod +x files/usr/bin/daed 2>/dev/null || true
        DAED_PREINSTALLED=true
      fi
    fi

    # 補充官方源具備的運行時依賴
    PACKAGES_TO_BUILD="$PACKAGES_TO_BUILD kmod-tun ca-bundle"
    # 從編譯命令中排除 daed，避免 apk 檢查 vmlinux-btf
    PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/daed//g; s/luci-app-daed//g; s/vmlinux-btf//g')
  fi

  PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | sed 's/luci-app-turboacc//g')
  echo "=========================================================="
  echo ""
fi

PACKAGES_TO_BUILD=$(echo "$PACKAGES_TO_BUILD" | xargs)
echo "最終交給套件管理器的軟體包列表: $PACKAGES_TO_BUILD"

# 7. 帶有智慧容錯自癒（Self-Healing）的打包程序
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
    echo ""
    echo "=========================================================="
    echo "⚠️ 偵測到以下軟體包在當前環境中無法滿足:"
    echo "   $all_culprits"
    echo "🔄 觸發自動自癒機制：清除缺失組件，重新構建..."
    echo "=========================================================="

    local cleaned_pkgs="$current_pkgs"
    for item in $all_culprits; do
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )$item( |\$)/ /g")
      cleaned_pkgs=$(echo "$cleaned_pkgs" | sed -E "s/(^| )luci-app-$item( |\$)/ /g")
      rm -f packages/*"$item"* 2>/dev/null || true
    done
    cleaned_pkgs=$(echo "$cleaned_pkgs" | xargs)

    echo "修正後的軟體包列表: $cleaned_pkgs"
    echo ""

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
