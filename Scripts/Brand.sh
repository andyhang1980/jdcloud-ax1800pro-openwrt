#!/bin/bash
# QWRT 品牌定制：把 ImmortalWrt / JDCloud 标识全部改成 QWRT
set -u
W="${1:-.}"
echo "[brand] QWRT branding -> $W"

# 1) openwrt_release / os-release：改生成模板，不依赖内部变量定义位置
BF="$W/package/base-files/Makefile"
if [ -f "$BF" ]; then
	sed -i "s|DISTRIB_ID='\$(DISTRIB_ID)'|DISTRIB_ID='QWRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|DISTRIBUTION='\$(DISTRIBUTION)'|DISTRIBUTION='QWRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|DISTRIB_REV='\$(DISTRIBUTION_REV)'|DISTRIB_REV='QWRT'|g" "$BF" 2>/dev/null || true
	sed -i "s|^DISTRIB_ID=.*|DISTRIB_ID='QWRT'|; s|^DISTRIBUTION=.*|DISTRIBUTION='QWRT'|; s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='QWRT firmware'|" "$BF" 2>/dev/null || true
	echo "  [ok] base-files Makefile patched"
fi
for FI in "$W/include/build.info" "$W/include/version.sh"; do
	[ -f "$FI" ] && sed -i "s|^DISTRIB_ID=.*|DISTRIB_ID='QWRT'|; s|^DISTRIBUTION=.*|DISTRIBUTION='QWRT'|; s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='QWRT firmware'|" "$FI" 2>/dev/null || true
done

# 2) SSH 登录横幅
mkdir -p "$W/package/base-files/files/etc"
cat > "$W/package/base-files/files/etc/banner" <<'BANNER'
          \/      \/  BE FREE AND UNAFRAID  \/
 -----------------------------------------------------
 QWRT AX1800 Pro (RE-SS-01) -- OpenWrt qualcommax/ipq60xx
 -----------------------------------------------------
BANNER
echo "  [ok] banner written"

# 3) 设备定义里的厂商/型号（影响 status 页「型号」与 metadata）
IMK="$W/target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$IMK" ]; then
	sed -i 's|^[[:space:]]*DEVICE_VENDOR[[:space:]]*:=[[:space:]]*JDCloud|	DEVICE_VENDOR := QWRT|' "$IMK"
	sed -i 's|^[[:space:]]*DEVICE_MODEL[[:space:]]*:=[[:space:]]*RE-SS-01|	DEVICE_MODEL := QWRT AX1800 Pro|' "$IMK"
	echo "  [ok] device mk patched"
fi

# 4) 设备树 model 属性（status 页「型号」的权威来源）
for DF in "$W"/target/linux/qualcommax/dts/*.dts "$W"/target/linux/qualcommax/dts/*.dtsi; do
	[ -f "$DF" ] || continue
	sed -i 's|^[[:space:]]*model[[:space:]]*=[[:space:]]*"JDCloud AX1800 Pro"|	model = "QWRT AX1800 Pro";|' "$DF" 2>/dev/null || true
done
echo "  [ok] dts model patched"

# 5) host_model 兜底
mkdir -p "$W/package/base-files/files/etc/sysinfo"
echo 'QWRT AX1800 Pro (RE-SS-01)' > "$W/package/base-files/files/etc/sysinfo/model"
echo "  [ok] sysinfo/model written"

echo "[brand] done"
