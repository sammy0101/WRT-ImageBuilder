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
