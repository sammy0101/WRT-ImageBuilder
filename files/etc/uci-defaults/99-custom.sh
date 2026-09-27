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

# 3. 強制配置靜態 LAN IP 為使用者自訂網址 (不再退回 DHCP)
echo "配置 LAN IP 為固定網址: $TARGET_LAN_IP" >> "$LOG_FILE"
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$TARGET_LAN_IP"
uci set network.lan.netmask='255.255.255.0'

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

# 5. 防火牆允許訪問
uci set firewall.@zone[1].input='ACCEPT'

uci commit network
uci commit firewall

# 6. 若存在 daed 核心，確保開機自動啟用自啟
if [ -f "/etc/init.d/daed" ]; then
    echo "啟用 daed 開機自啟動服務..." >> "$LOG_FILE"
    /etc/init.d/daed enable 2>/dev/null || true
    /etc/init.d/daed restart 2>/dev/null || true
fi

echo "=== 首航配置完成 ===" >> "$LOG_FILE"
exit 0
