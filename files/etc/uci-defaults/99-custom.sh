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
