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
		cp -rf $(find "$CLONE_DIR"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune) ./
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

# homeproxy：VIKINGYFY/homeproxy 已被删除，feed（immortalwrt/luci）自带 luci-app-homeproxy，不再覆盖
# UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"

UPDATE_PACKAGE "mihomo" "morytyann/OpenWrt-mihomo" "main"
UPDATE_PACKAGE "nekoclash" "Thaolga/luci-app-nekoclash" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "ssr-plus" "fw876/helloworld" "master"

UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5"
UPDATE_PACKAGE "vnt" "lazyoop/networking-artifact" "main" "pkg"
UPDATE_PACKAGE "easytier" "lazyoop/networking-artifact" "main" "pkg"

# 不兼容官方argon
# UPDATE_PACKAGE "luci-app-advancedplus" "VIKINGYFY/packages" "main" "pkg"

UPDATE_PACKAGE "gecoosac" "lwb1978/openwrt-gecoosac" "main"
UPDATE_PACKAGE "tailscale" "asvow/luci-app-tailscale" "main"
# wolplus：VIKINGYFY/packages 里已无 wolplus，改用 siwind 的独立仓库（仓库根即插件目录）
UPDATE_PACKAGE "wolplus" "siwind/luci-app-wolplus" "main"

# golang：不再覆盖 —— 上游换的 sbwml 22.x 是 Go 1.22，编不过 feed 里 runc>=1.23 的要求，
# feed 自带 golang 与其 runc 版本是配套的，直接用 feed 的
# rm -rf ./.clone-golang
# ... (原替换逻辑已停用)

# alist 直接克隆已停用：cgofuse 编译需要 fuse.h，交叉编译下头文件/标签都对不上（run6 失败原因）
# rm -rf ./.clone-alist
# ...

if [[ $WRT_REPO != *"immortalwrt"* ]]; then
	UPDATE_PACKAGE "qmi-wwan" "immortalwrt/wwan-packages" "master" "pkg"
fi

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
