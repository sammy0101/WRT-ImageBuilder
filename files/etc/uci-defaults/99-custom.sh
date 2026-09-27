#!/bin/sh
# ==============================================================================
# 首航初始化腳本：開機首次啟動自動執行一次後自我銷毀
# ==============================================================================

LOG_FILE="/tmp/uci-defaults-init.log"
echo "=== 開始執行首航網路與系統配置 $(date) ===" > "$LOG_FILE"

# 1. 讀取自訂網路參數設定檔
NET_CONF="/etc/custom_network_config"
if [ -f "$NET_CONF" ]; then
    . "$NET_CONF"
fi

TARGET_LAN_IP="${CUSTOM_LAN_IP:-192.168.100.1}"
IS_BYPASS="${IS_BYPASS_ROUTER:-false}"
GATEWAY="${GATEWAY_IP:-192.168.100.1}"
DNS_LIST="${DNS_SERVERS:-192.168.100.1 8.8.8.8}"

# 2. 網路配置 (旁路由 vs 主路由模式)
if [ "$IS_BYPASS" = "true" ]; then
    echo "==========================================================" >> "$LOG_FILE"
    echo "  正在套用【旁路由模式】配置..." >> "$LOG_FILE"
    echo "  本機 IP: $TARGET_LAN_IP" >> "$LOG_FILE"
    echo "  主路由網關: $GATEWAY" >> "$LOG_FILE"
    echo "  自訂 DNS: $DNS_LIST" >> "$LOG_FILE"
    echo "==========================================================" >> "$LOG_FILE"

    # (A) 配置 LAN 靜態 IP、網關與 DNS
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$GATEWAY"
    
    # 遍歷加入 DNS 清單
    uci -q delete network.lan.dns
    for dns_ip in $DNS_LIST; do
        uci add_list network.lan.dns="$dns_ip"
    done

    # (B) 【最重要】關閉旁路由的 DHCP 伺服器 (防止與主路由器衝突)
    uci set dhcp.lan.ignore='1'
    uci -q delete dhcp.lan.dhcpv6
    uci -q delete dhcp.lan.ra
    uci -q delete dhcp.lan.ra_slaac
    uci -q delete dhcp.lan.ra_flags

    # (C) 【最重要】開啟 LAN 防火牆動態偽裝 (NAT Masquerade)，解決單向流量問題
    uci set firewall.@zone[0].masq='1'
    uci set firewall.@zone[0].mtu_fix='1'

    # (D) 旁路由通常不需要獨立 WAN 接口，停用避免衝突
    uci set network.wan.disabled='1' 2>/dev/null || true
    uci set network.wan6.disabled='1' 2>/dev/null || true

else
    echo "套用【標準主路由模式】: LAN IP=$TARGET_LAN_IP" >> "$LOG_FILE"
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    uci set dhcp.lan.ignore='0'

    # PPPoE 撥號配置
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
fi

# 3. 防火牆允許入站訪問
uci set firewall.@zone[1].input='ACCEPT' 2>/dev/null || true

uci commit network
uci commit dhcp
uci commit firewall

# 4. 【註冊與啟用 DAED】
if [ -f "/usr/bin/daed" ] || [ -f "/etc/init.d/daed" ]; then
    echo "正在初始化 DAED 配置與自啟動服務..." >> "$LOG_FILE"
    mkdir -p /etc/daed /var/log/daed
    chmod +x /usr/bin/daed 2>/dev/null || true
    chmod +x /etc/init.d/daed 2>/dev/null || true
    
    /etc/init.d/daed enable 2>/dev/null || true
    /etc/init.d/daed restart 2>/dev/null || true
    
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
fi

echo "=== 首航配置完成 ===" >> "$LOG_FILE"
exit 0
