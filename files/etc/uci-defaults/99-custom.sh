#!/bin/sh
# ==============================================================================
# 首航初始化腳本：開機首次啟動自動執行一次後自我銷毀
# ==============================================================================

LOG_FILE="/tmp/uci-defaults-init.log"
echo "=== 開始執行首航網路配置 $(date) ===" > "$LOG_FILE"

# 1. 讀取自訂網路參數設定檔
NET_CONF="/etc/custom_network_config"
if [ -f "$NET_CONF" ]; then
    . "$NET_CONF"
fi

TARGET_LAN_IP="${CUSTOM_LAN_IP:-192.168.100.1}"
IS_BYPASS="${IS_BYPASS_ROUTER:-false}"
GATEWAY="${GATEWAY_IP:-192.168.100.2}"
DNS_LIST="${DNS_SERVERS:-192.168.100.2 8.8.8.8}"

# 2. 網路配置 (旁路由 vs 主路由模式)
if [ "$IS_BYPASS" = "true" ]; then
    echo "套用【旁路由模式】: IP=$TARGET_LAN_IP, GW=$GATEWAY" >> "$LOG_FILE"

    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$GATEWAY"
    
    uci -q delete network.lan.dns
    for dns_ip in $DNS_LIST; do
        uci add_list network.lan.dns="$dns_ip"
    done

    # 關閉旁路由 DHCP 伺服器
    uci set dhcp.lan.ignore='1'
    uci -q delete dhcp.lan.dhcpv6
    uci -q delete dhcp.lan.ra
    uci -q delete dhcp.lan.ra_slaac
    uci -q delete dhcp.lan.ra_flags

    # 開啟 LAN 防火牆動態偽裝 (NAT Masquerade)
    uci set firewall.@zone[0].masq='1'
    uci set firewall.@zone[0].mtu_fix='1'

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
fi

# 3. 防火牆允許入站訪問
uci set firewall.@zone[0].input='ACCEPT'
uci set firewall.@zone[1].input='ACCEPT' 2>/dev/null || true

uci commit network
uci commit dhcp
uci commit firewall

echo "=== 首航配置完成 ===" >> "$LOG_FILE"
exit 0
