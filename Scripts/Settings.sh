#!/bin/bash

#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_CI-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")
#修改默认WIFI名
sed -i "s/\.ssid=.*/\.ssid=$WRT_WIFI/g" $(find ./package/kernel/mac80211/ ./package/network/config/ -type f -name "mac80211.*")

# 默认 WiFi 规格（首启 uci-defaults 落地）：2.4G=QWRT2.4G，5G=QWRT5G，WPA2 加密，密码 12345678
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-wifi-defaults << 'WIFIEOF'
#!/bin/sh
[ -f /etc/config/wireless ] || timeout 15 wifi config >/dev/null 2>&1 || true
n=0
while uci -q get "wireless.@wifi-iface[$n]" >/dev/null 2>&1; do
	dev=$(uci -q get "wireless.@wifi-iface[$n].device")
	band=$(uci -q get "wireless.$dev.band")
	case "$band" in
		2g) ssid="QWRT2.4G" ;;
		5g) ssid="QWRT5G" ;;
		*)  ssid="QWRT" ;;
	esac
	uci -q set "wireless.@wifi-iface[$n].ssid=$ssid"
	uci -q set "wireless.@wifi-iface[$n].encryption=psk2"
	uci -q set "wireless.@wifi-iface[$n].key=12345678"
	n=$((n+1))
done
uci -q commit wireless
exit 0
WIFIEOF
echo "wifi defaults: QWRT2.4G/QWRT5G psk2 12345678"
# WiFi 默认设置改用 init 脚本：uci-defaults 在 boot 早期（wifi 服务启动前）执行，
# 改的配置会被后续 wifi 启动覆盖回构建默认值；init 脚本 START=99 在 wifi 之后执行，确保生效。
cat > ./package/base-files/files/etc/init.d/qwrt-wifi-defaults << 'WIFIEOF'
#!/bin/sh /etc/rc.common
START=99
REQUIRES="wifi"
[ -f /etc/wrt-wifi.done ] && exit 0
start() {
	i=0
	while [ $i -lt 4 ]; do
		dev=$(uci -q get wireless.@wifi-iface[$i].device)
		[ -n "$dev" ] || break
		band=$(uci -q get wireless.$dev.band)
		if [ "$band" = "5g" ]; then ssid="QWRT5G"; elif [ "$band" = "2g" ]; then ssid="QWRT2.4G"; else ssid="QWRT"; fi
		uci -q set wireless.@wifi-iface[$i].ssid="$ssid"
		uci -q set wireless.@wifi-iface[$i].encryption="psk2"
		uci -q set wireless.@wifi-iface[$i].key="12345678"
		i=$((i+1))
	done
	uci -q commit wireless
	touch /etc/wrt-wifi.done
}
WIFIEOF
echo "wifi init script written"
# 服务菜单排序 + Docker 改名（首启落地，刷机后不会回退）
# 目标顺序：SSR Plus+ / HomeProxy / PassWall / mosdns / Docker / 带宽监控 / 网络唤醒Plus
cat > ./package/base-files/files/etc/uci-defaults/97-menu-order << 'MENUEOF'
#!/bin/sh
[ -f /etc/wrt-menu-order.done ] && exit 0

setfirst() {
	f="$1"; old="$2"; new="$3"
	[ -f "$f" ] || return 0
	awk -v old="$old" -v new="$new" 'BEGIN{done=0} { if (!done && index($0, old) > 0) { sub(old, new); done=1 } print }' "$f" > "$f.wrt" && mv "$f.wrt" "$f"
}

L=/usr/share/luci/menu.d
C=/usr/lib/lua/luci/controller
setfirst "$L/luci-app-homeproxy.json" '"order": 10,' '"order": 20,'
setfirst "$L/luci-app-mosdns.json"    '"order": 30,' '"order": 40,'
setfirst "$L/luci-app-dockerman.json" '"title": "Dockerman JS"' '"title": "Docker"'
setfirst "$L/luci-app-dockerman.json" '"order": "60",' '"order": 50,'
setfirst "$L/luci-app-nlbwmon.json"   '"order": 80,' '"order": 60,'
[ -f "$C/shadowsocksr.lua" ] && sed -i 's|_("ShadowSocksR Plus+"), 10)|_("ShadowsocksR Plus+"), 10)|' "$C/shadowsocksr.lua"
[ -f "$C/passwall.lua" ] && sed -i 's|_("Pass Wall"), -1)|_("PassWall"), 30)|g' "$C/passwall.lua"
[ -f "$C/wolplus.lua" ] && sed -i 's|_("wolplus"), 95)|_("WOL Plus"), 70)|' "$C/wolplus.lua"

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null
touch /etc/wrt-menu-order.done
exit 0
MENUEOF
echo "menu order: services reordered, dockerman renamed to Docker"
# 品牌统一：去掉 LibWrt 痕迹，全部替换为 QWRT（os-release / device_info / uhttpd 证书 CN）
cat > ./package/base-files/files/etc/uci-defaults/96-brand-release << 'BRANDEOF'
#!/bin/sh
[ -f /etc/wrt-brand.done ] && exit 0

# 1) /usr/lib/os-release: LibWrt -> QWRT
OSR=/usr/lib/os-release
if [ -f "$OSR" ]; then
	sed -i 's/LibWrt/QWRT/g; s/ImmortalWrt/QWRT/g; s/^ID=.*/ID="qwrt"/' "$OSR"
	sed -i 's|https://immortalwrt.org/|https://github.com/andyhang1980/jdcloud-ax1800pro-openwrt|g' "$OSR"
	sed -i 's|https://github.com/immortalwrt/immortalwrt|https://github.com/andyhang1980/jdcloud-ax1800pro-openwrt|g' "$OSR"
	sed -i 's|https://downloads.immortalwrt.org/|https://github.com/andyhang1980/jdcloud-ax1800pro-openwrt/releases|g' "$OSR"
	sed -i 's|^OPENWRT_DEVICE_PRODUCT=.*|OPENWRT_DEVICE_PRODUCT="JDCloud RE-SS-01"|' "$OSR"
fi

# 2) /etc/os-release: 构建时是未替换的 %D %V 模板，直接用正确的 /usr/lib/os-release 覆盖
[ -f "$OSR" ] && cp "$OSR" /etc/os-release

# 3) /etc/openwrt_release: DISTRIB_ID / DESCRIPTION 统一为 QWRT
if [ -f /etc/openwrt_release ]; then
	sed -i "s/^DISTRIB_ID=.*/DISTRIB_ID='QWRT'/" /etc/openwrt_release
	sed -i "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='QWRT SNAPSHOT'/" /etc/openwrt_release
fi

# 4) device_info
[ -f /etc/device_info ] && sed -i 's/LibWrt/QWRT/g; s/ImmortalWrt/QWRT/g; s|https://immortalwrt.org/|https://github.com/andyhang1980/jdcloud-ax1800pro-openwrt|g' /etc/device_info

# 5) uhttpd CN (不重启服务，避免早期启动缺熵阻塞)
if [ -f /etc/config/uhttpd ]; then
	sed -i "s/option commonname 'LibWrt'/option commonname 'QWRT'/" /etc/config/uhttpd
	sed -i "s/option commonname 'ImmortalWrt'/option commonname 'QWRT'/" /etc/config/uhttpd
fi
# 只删旧证书，uhttpd 下次正常启动时自动用新 CN 重新自签
rm -f /etc/uhttpd.crt /etc/uhttpd.key 2>/dev/null

touch /etc/wrt-brand.done
exit 0
BRANDEOF

# === 默认 root 密码 = password (出厂即带，LuCI 不再提示"未设置密码") ===
SH=./package/base-files/files/etc/shadow
if [ -f "$SH" ]; then
	# 空密码 root::: -> 带哈希; 已有密码则跳过
	if grep -q "^root:::" "$SH"; then
		sed -i 's|^root:::|root:$5$a18LB5uIm0l1ZTqh$ElmBgO88pp6EUvah0RZCJdUOqXA/GVL//2agVZ8tS0A:20769:|' "$SH"
		echo "[Settings] default root password set to: password"
	fi
fi
echo "brand: LibWrt -> QWRT (os-release/device_info/uhttpd CN)"

# 构建树里能顺手改的直接改（找不到也不报错）
for f in $(find ./package ./include -name 'os-release' -o -name 'version.mk' -o -name 'uhttpd.config' -o -name 'device_info' 2>/dev/null); do
	sed -i 's/LibWrt/QWRT/g; s/libwrt/qwrt/g; s/LIBWRT/QWRT/g' "$f" 2>/dev/null
done

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
if [[ $WRT_TARGET == *"IPQ"* ]]; then
	# LiBwrt 25.12-nss 自带 nss feed，不禁用
	echo "CONFIG_FEED_nss_packages=y" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=y" >> ./.config
fi

# 想要剔除的
# echo "CONFIG_PACKAGE_htop=n" >> ./.config
# echo "CONFIG_PACKAGE_iperf3=n" >> ./.config
# 不再强制剔除 wolplus/tailscale/advancedplus/kucat，以 Config/GENERAL.txt 的“增加插件”为准
# echo "CONFIG_PACKAGE_luci-app-wolplus=n" >> ./.config
# echo "CONFIG_PACKAGE_luci-app-tailscale=n" >> ./.config
# echo "CONFIG_PACKAGE_luci-app-advancedplus=n" >> ./.config
# echo "CONFIG_PACKAGE_luci-theme-kucat=n" >> ./.config

# 可以让FinalShell查看文件列表并且ssh连上不会自动断开
echo "CONFIG_PACKAGE_openssh-sftp-server=y" >> ./.config
# 解析、查询、操作和格式化 JSON 数据
echo "CONFIG_PACKAGE_jq=y" >> ./.config
# 简单明了的系统资源占用查看工具
echo "CONFIG_PACKAGE_btop=y" >> ./.config
# 多网盘存储 —— alist 暂时剔除：sbwml 版缺 libfuse 依赖，cgofuse 在交叉编译下 fuse.h 找不到
# echo "CONFIG_PACKAGE_luci-app-alist=y" >> ./.config
# 强大的工具(需要添加源或git clone)
# echo "CONFIG_PACKAGE_luci-app-lucky=y" >> ./.config
# 网络通信工具
echo "CONFIG_PACKAGE_curl=y" >> ./.config
# CPU 性能优化调节设置
# echo "CONFIG_PACKAGE_luci-app-cpufreq=y" >> ./.config
# 图形化流量监控
# echo "CONFIG_PACKAGE_luci-app-wrtbwmon=y" >> ./.config
# bbr加速+turboacc
echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> ./.config
# BBR 拥塞控制算法
# echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> ./.config
# BBR 拥塞控制算法(终端侧) + CAKE 一种现代化的队列管理算法(路由侧)
# echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
# echo "CONFIG_PACKAGE_kmod-sched-cake=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> ./.config
# echo "CONFIG_DEFAULT_tcp_bbr=y" >> ./.config
# docker(只能集成)
echo "CONFIG_PACKAGE_luci-app-dockerman=y" >> ./.config

#自己增加的（qB不编译最新的）
echo "CONFIG_PACKAGE_autosamba=y" >> ./.config

echo "CONFIG_PACKAGE_nfs-kernel-server=y" >> ./.config
echo "CONFIG_PACKAGE_nfs-kernel-server-utils=y" >> ./.config
echo "CONFIG_PACKAGE_nfs-utils=y" >> ./.config
echo "CONFIG_PACKAGE_nfs-utils-libs=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-nfs=y" >> ./.config

# DNS：SmartDNS 换成 mosdns（菜单：服务 → mosdns）
echo "CONFIG_PACKAGE_mosdns=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> ./.config

echo "CONFIG_PACKAGE_adguardhome=y" >> ./.config

echo "CONFIG_PACKAGE_luci-app-passwall=y" >> ./.config

echo "CONFIG_PACKAGE_aria2=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-aria2=y" >> ./.config

# # XDP 一种高级数据处理技术，旨在提高网络数据包处理的效率和性能。它允许在网络数据包进入内核的更早阶段进行处理，从而减少延迟和提高吞吐量。
# # 基本 XDP 支持
echo "CONFIG_XDP=y" >> ./.config
# # XDP Sockets
echo "CONFIG_XDP_SOCKETS=y" >> ./.config
# # BPF 子系统支持（XDP 是 BPF 的一部分）
echo "CONFIG_BPF=y" >> ./.config
echo "CONFIG_BPF_SYSCALL=y" >> ./.config
# # BPF 相关选项（为了全面支持 XDP）
echo "CONFIG_NET_CLS_BPF=y" >> ./.config
echo "CONFIG_NET_ACT_BPF=y" >> ./.config
echo "CONFIG_BPF_JIT=y" >> ./.config
echo "CONFIG_HAVE_EBPF_JIT=y" >> ./.config
echo "CONFIG_BPF_EVENTS=y" >> ./.config
echo "CONFIG_BPF_STREAM_PARSER=y" >> ./.config
# # eBPF 和 JIT 编译器支持
echo "CONFIG_HAVE_BPF_JIT=y" >> ./.config
echo "CONFIG_BPF_JIT_ALWAYS_ON=y" >> ./.config
# # 内核调试信息（可选）: 如果需要调试，可以选择启用内核调试和相关日志支持
# echo "CONFIG_DEBUG_INFO=n" >> ./.config
# echo "CONFIG_DEBUG_INFO_REDUCED=n" >> ./.config
