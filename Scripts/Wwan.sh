#!/bin/bash
# QWRT 随身WiFi WAN：预置 wwan 接口、防火墙 zone、USB 网口自动绑定
set -u
W="${1:-.}"
echo "[wwan] USB 随身WiFi as WAN -> $W"

# 1) uci-defaults：首次启动建 wwan 接口 + 把 wwan 加进 wan 防火墙 zone
UD="$W/package/base-files/files/etc/uci-defaults"
mkdir -p "$UD"
cat > "$UD/qwrt-wwan.sh" <<'UCI'
#!/bin/sh
# QWRT 随身WiFi WAN 预置
if ! uci -q get network wwan >/dev/null 2>&1; then
	uci -q add network wwan >/dev/null 2>&1 || uci -q add network wwan
fi
uci -q get network wwan >/dev/null 2>&1 || exit 0
uci set network wwan.proto='dhcp'
uci set network wwan.device='wwan'
uci commit network

uci -q get firewall wan >/dev/null 2>&1 || exit 0
uci -q get firewall wan interface wwan >/dev/null 2>&1 || uci add_list firewall.wan.interface=wwan
uci commit firewall
UCI
chmod +x "$UD/qwrt-wwan.sh"
echo "  [ok] uci-defaults written"

# 2) hotplug：USB 网口出现时自动把 wwan.device 指向它
HP="$W/package/base-files/files/etc/hotplug.d/net"
mkdir -p "$HP"
cat > "$HP/40-qwrt-wwan" <<'HP'
#!/bin/sh
# QWRT: USB 随身WiFi 网口自动绑定到 wwan 接口
case "${DEVPATH}" in
	*/sys/class/net/*) ;;
	*) exit 0 ;;
esac
n="${DEVPATH##*/sys/class/net/}"
[ -n "$n" ] || exit 0
[ -e "$DEVPATH/device" ] || exit 0
readlink -f "$DEVPATH/device" 2>/dev/null | grep -q '/usb' || exit 0
uci -q get network wwan >/dev/null 2>&1 || exit 0
cur=$(uci -q get network wwan device)
[ "$cur" = "$n" ] && exit 0
uci set network wwan device="$n"
uci commit network
/etc/init.d/netifd reload >/dev/null 2>&1 || /etc/init.d/network reload >/dev/null 2>&1
HP
chmod +x "$HP/40-qwrt-wwan"
echo "  [ok] hotplug written"

echo "[wwan] done"
