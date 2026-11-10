#!/bin/bash

#安装和更新软件包
# 克隆走 GITHUB_TOKEN 认证（避免 runner IP 被限流），带重试；
# 只有克隆成功才移除 feed 旧版本 —— 克隆失败时自动回退用 feed 里的版本
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local REPO_NAME=$(echo $PKG_REPO | cut -d '/' -f 2)
	local CLONE_DIR="./.clone-$REPO_NAME"
	local AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${PKG_REPO}.git"

	rm -rf "$CLONE_DIR"

	local OK=0
	for i in 1 2 3 4 5; do
		if git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "$AUTH_URL" "$CLONE_DIR" 2>/dev/null; then
			OK=1
			break
		fi
		echo "clone retry $i/5: $PKG_REPO@$PKG_BRANCH"
		sleep $((i * 5))
	done

	if [ "$OK" != "1" ]; then
		echo "WARN: clone failed for $PKG_REPO@$PKG_BRANCH, keep feed version of *$PKG_NAME*"
		rm -rf "$CLONE_DIR"
		return 1
	fi

	# 克隆成功，移除 feed 里的旧版本
	rm -rf $(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune) 2>/dev/null || true

	if [[ $PKG_SPECIAL == "pkg" ]]; then
		SRC=$(find "$CLONE_DIR"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune | head -1)
		[ -z "$SRC" ] && { echo "WARN: '$PKG_NAME' not found inside $PKG_REPO, skip"; rm -rf "$CLONE_DIR"; return 1; }
		cp -rf "$SRC" ./
		rm -rf "$CLONE_DIR"
	elif [[ $PKG_SPECIAL == "name" ]]; then
		mv -f "$CLONE_DIR" "$PKG_NAME"
	else
		mv -f "$CLONE_DIR" "$REPO_NAME"
	fi

	echo "updated: $PKG_NAME <= $PKG_REPO@$PKG_BRANCH"
}

#UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"

# 使用原版官方的
# UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"

# 主题 kucat：上游原来的 js 分支已删除，只剩 master
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"

# design 主题：从 Lean 的 luci 分支取（自带 ucode 模板，适配 25.12 新版 LuCI）
# 仓库根是 luci 单体仓库，只提取 themes/luci-theme-design 一个目录
UPDATE_PACKAGE "luci-theme-design" "coolsnowwolf/luci" "openwrt-25.12" "pkg"
# 原 Makefile 写的是 `include ../../luci.mk`（相对 luci 仓库根），
# 拷到 package/ 后相对路径失效，改指 feeds 里的 luci.mk
if [ -f ./luci-theme-design/Makefile ]; then
	sed -i 's|include \.\./\.\./luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' ./luci-theme-design/Makefile
	echo "luci-theme-design: include path fixed"
fi

# 主题 CSS 补丁：定时重启页 6 列+操作列超宽被裁剪 → 固定布局收缩
TCSS="./luci-theme-design/htdocs/luci-static/design/css/style.css"
if [ -f "$TCSS" ] && ! grep -q 'WRT-AUTOREBOOT-FIX' "$TCSS"; then
	printf '\n' >> "$TCSS"
	cat "$GITHUB_WORKSPACE/Scripts/patches/design-autoreboot-fix.css" >> "$TCSS"
	echo "theme css: autoreboot table fix applied"
fi

# homeproxy：VIKINGYFY/homeproxy 已被删除，feed（immortalwrt/luci）自带 luci-app-homeproxy，不再覆盖
# UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"

UPDATE_PACKAGE "mihomo" "morytyann/OpenWrt-mihomo" "main"
UPDATE_PACKAGE "nekoclash" "Thaolga/luci-app-nekoclash" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "ssr-plus" "fw876/helloworld" "master"

# SSR Plus 导入改成模态弹窗（原生 prompt() 太丑，参考 homeproxy 的导入分享链接）
SSR_DIR=$(find ./ -maxdepth 4 -type d -name 'luci-app-ssr-plus' | head -1)
SSR_PATCH="$GITHUB_WORKSPACE/Scripts/patches/ssrplus-ssrurl-modal.htm"
if [ -n "$SSR_DIR" ] && [ -f "$SSR_PATCH" ] && [ -f "$SSR_DIR/luasrc/view/shadowsocksr/ssrurl.htm" ]; then
	cp -f "$SSR_PATCH" "$SSR_DIR/luasrc/view/shadowsocksr/ssrurl.htm"
	echo "ssr-plus: import modal applied"
fi

# TurboACC 加速设置页（chenmozhijin 的 firewall4 版；状态页会识别 QCA-NSS-ECM）
UPDATE_PACKAGE "turboacc" "chenmozhijin/turboacc" "luci" "pkg"
# 默认关掉软件/硬件/SFE 流分载 —— 硬件加速由 NSS ECM 负责，避免双加速冲突；保留 BBR + FullCone
TC_CFG="./luci-app-turboacc/root/etc/config/turboacc"
if [ -f "$TC_CFG" ]; then
	sed -i "s/option sw_flow '1'/option sw_flow '0'/; s/option hw_flow '1'/option hw_flow '0'/; s/option sfe_flow '1'/option sfe_flow '0'/" "$TC_CFG"
	echo "turboacc: sw/hw/sfe flow off by default (NSS ECM owns offload)"
fi

UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5"

# NSS 硬件加速状态页（菜单：状态 → NSS Status，读 ECM/qca-nss-drv 的 debugfs）
# 注意：该仓库根目录就是包目录（Makefile 在根），必须用 name 模式整仓改名
UPDATE_PACKAGE "luci-app-nssstatus" "shadowvershh/luci-app-nssstatus" "main" "name"
UPDATE_PACKAGE "vnt" "lazyoop/networking-artifact" "main" "pkg"
UPDATE_PACKAGE "easytier" "lazyoop/networking-artifact" "main" "pkg"

# 不兼容官方argon
# UPDATE_PACKAGE "luci-app-advancedplus" "VIKINGYFY/packages" "main" "pkg"

UPDATE_PACKAGE "gecoosac" "lwb1978/openwrt-gecoosac" "main"
# tailscale 停用：feed 里没有 tailscale 二进制包，luci-app-tailscale 依赖解析失败（run7）
# UPDATE_PACKAGE "tailscale" "asvow/luci-app-tailscale" "main"
# wolplus：VIKINGYFY/packages 里已无 wolplus，改用 siwind 的独立仓库（仓库根即插件目录）
UPDATE_PACKAGE "wolplus" "siwind/luci-app-wolplus" "main"

# golang：不再覆盖 —— 上游换的 sbwml 22.x 是 Go 1.22，编不过 feed 里 runc>=1.23 的要求，
# feed 自带 golang 与其 runc 版本是配套的，直接用 feed 的
# rm -rf ./.clone-golang
# ... (原替换逻辑已停用)

# alist 直接克隆已停用：cgofuse 编译需要 fuse.h，交叉编译下头文件/标签都对不上（run6 失败原因）
# rm -rf ./.clone-alist
# ...

# qmi-wwan（wwan-packages 里的 QMI 用户态 + netifd qmi 协议后端）与 3ginfo-lite（3G/4G 信息页）
# 上游条件 `WRT_REPO != *"immortalwrt"*` 在本仓库恒为假（WRT_REPO 含 immortalwrt），一直跳过，这里无条件拉取
UPDATE_PACKAGE "qmi-wwan" "immortalwrt/wwan-packages" "master" "pkg"
UPDATE_PACKAGE "3ginfo-lite" "immortalwrt/wwan-packages" "master" "pkg"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-not}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	echo " "

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo "$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Pho 'PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)' $PKG_FILE | head -n 1)
		local PKG_VER=$(curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease|$PKG_MARK)) | first | .tag_name")
		local NEW_VER=$(echo $PKG_VER | sed "s/.*v//g; s/_/./g")
		local NEW_HASH=$(curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" "https://codeload.github.com/$PKG_REPO/tar.gz/$PKG_VER" | sha256sum | cut -b -64)
		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")

		echo "$OLD_VER $PKG_VER $NEW_VER $NEW_HASH"

		if [[ $NEW_VER =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
UPDATE_VERSION "sing-box"
