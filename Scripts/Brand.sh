#!/bin/bash
# WRT 品牌定制：把 ImmortalWrt / JDCloud 标识全部改成 WRT
set -u
W="${1:-.}"
echo "[brand] WRT branding -> $W"

# 1) openwrt_release / os-release：改生成模板，不依赖内部变量定义位置
BF="$W/package/base-files/Makefile"
if [ -f "$BF" ]; then
	sed -i "s|DISTRIB_ID='\$(DISTRIB_ID)'|DISTRIB_ID='WRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|DISTRIBUTION='\$(DISTRIBUTION)'|DISTRIBUTION='WRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|DISTRIB_REV='\$(DISTRIBUTION_REV)'|DISTRIB_REV='WRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|^DISTRIB_ID=.*|DISTRIB_ID='WRT'|; s|^DISTRIBUTION=.*|DISTRIBUTION='WRT'|; s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='WRT firmware'|" "$BF" 2>/dev/null || true
	echo "  [ok] base-files Makefile patched"
fi
for FI in "$W/include/build.info" "$W/include/version.sh"; do
	[ -f "$FI" ] && sed -i "s|^DISTRIB_ID=.*|DISTRIB_ID='WRT'|; s|^DISTRIBUTION=.*|DISTRIBUTION='WRT'|; s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='WRT firmware'|" "$FI" 2>/dev/null || true
done

# 2) SSH 登录横幅
mkdir -p "$W/package/base-files/files/etc"
cat > "$W/package/base-files/files/etc/banner" <<'BANNER'
          \/      \/  BE FREE AND UNAFRAID  \/
 -----------------------------------------------------
 WRT AX1800 Pro (RE-SS-01) -- OpenWrt qualcommax/ipq60xx
 -----------------------------------------------------
BANNER
echo "  [ok] banner written"

# 3) 设备定义里的厂商/型号（影响 status 页「型号」与 metadata）
IMK="$W/target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$IMK" ]; then
	sed -i 's|^[[:space:]]*DEVICE_VENDOR[[:space:]]*:=[[:space:]]*JDCloud|	DEVICE_VENDOR := WRT|' "$IMK"
	sed -i 's|^[[:space:]]*DEVICE_MODEL[[:space:]]*:=[[:space:]]*RE-SS-01|	DEVICE_MODEL := WRT AX1800 Pro|' "$IMK"
	echo "  [ok] device mk patched"
fi

# 4) 设备树 model 属性（status 页「型号」的权威来源）
for DF in "$W"/target/linux/qualcommax/dts/*.dts "$W"/target/linux/qualcommax/dts/*.dtsi; do
	[ -f "$DF" ] || continue
	sed -i 's|^[[:space:]]*model[[:space:]]*=[[:space:]]*"JDCloud AX1800 Pro"|	model = "WRT AX1800 Pro";|' "$DF" 2>/dev/null || true
done
echo "  [ok] dts model patched"

# 5) host_model 兜底
mkdir -p "$W/package/base-files/files/etc/sysinfo"
echo 'WRT AX1800 Pro (RE-SS-01)' > "$W/package/base-files/files/etc/sysinfo/model"
echo "  [ok] sysinfo/model written"

# 6) openwrt_release 直接覆盖（编译产物，最可靠）
OR="$W/package/base-files/files/etc/openwrt_release"
cat > "$OR" <<'OR'
DISTRIB_ID='WRT'
DISTRIB_RELEASE='SNAPSHOT'
DISTRIB_REVISION='r0'
DISTRIB_TARGET='qualcommax/ipq60xx'
DISTRIB_ARCH='aarch64_cortex-a53'
DISTRIB_DESCRIPTION='WRT SNAPSHOT'
DISTRIB_TAINTS='no-all busybox override'
OR
echo "  [ok] openwrt_release overridden"

echo "[brand] done"
