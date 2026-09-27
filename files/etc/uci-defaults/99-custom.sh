#!/bin/sh
# ==============================================================================
# 首航初始化腳本：開機首次啟動自動執行一次後自我銷毀
# ==============================================================================

LOG_FILE="/tmp/uci-defaults-init.log"
echo "=== 開始執行首航配置 $(date) ===" > "$LOG_FILE"

# 1. 讀取自訂 LAN IP 設定
if [ -f "/etc/custom_lan_ip" ]; then
    . /etc/custom_lan_ip
fi
TARGET_LAN_IP="${CUSTOM_LAN_IP:-192.168.100.1}"

# 2. 強制配置靜態 LAN IP
echo "配置 LAN IP 為固定網址: $TARGET_LAN_IP" >> "$LOG_FILE"
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$TARGET_LAN_IP"
uci set network.lan.netmask='255.255.255.0'

# 3. PPPoE 撥號配置
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

# 4. 防火牆允許入站訪問
uci set firewall.@zone[1].input='ACCEPT'

uci commit network
uci commit firewall

# 5. 【註冊與啟用 DAED】
if [ -f "/usr/bin/daed" ] || [ -f "/etc/init.d/daed" ]; then
    echo "正在初始化 DAED 配置與自啟動服務..." >> "$LOG_FILE"
    
    # 建立預設配置檔目錄
    mkdir -p /etc/daed /var/log/daed
    
    # 確保執行權限
    chmod +x /usr/bin/daed 2>/dev/null || true
    chmod +x /etc/init.d/daed 2>/dev/null || true
    
    # 開啟服務自啟動
    /etc/init.d/daed enable 2>/dev/null || true
    /etc/init.d/daed start 2>/dev/null || true
    
    # 刷新 LuCI 索引快取，確保 Web 選單立即出現
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
fi

echo "=== 首航配置完成 ===" >> "$LOG_FILE"
exit 0
