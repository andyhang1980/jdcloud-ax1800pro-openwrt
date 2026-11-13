#!/bin/sh
# 确保 rust 的 bootstrap.toml 存在且 llvm.download-ci-llvm = false
# 用法: rust-llvm-fix.sh <bootstrap.toml 路径>
#
# 背景: OpenWrt 的 rust 包 configure 阶段实际从未执行(日志无 Configure the build 标记)，
#       所以 Makefile 里 HOST_CONFIGURE_ARGS 的 --set=llvm.download-ci-llvm=false 从未生效；
#       x.py 自动创建默认 bootstrap.toml 后会去 ci-artifacts.rust-lang.org 下载 LLVM，
#       该 CI 构件过期被删 -> 404 -> package/feeds/packages/rust [host] failed to build。
#       Rust 官方错误信息给出的修复就是把 download-ci-llvm 设为 false(改为本地构建 LLVM)。

f="$1"
[ -n "$f" ] || exit 0

if [ ! -f "$f" ]; then
	printf 'change-id = 154508\n[llvm]\ndownload-ci-llvm = false\n' > "$f"
	echo "rust-llvm-fix: created $f"
	exit 0
fi

if grep -q 'download-ci-llvm' "$f" 2>/dev/null; then
	sed -i 's/^[[:space:]]*download-ci-llvm[[:space:]]*=.*/download-ci-llvm = false/' "$f"
	echo "rust-llvm-fix: forced download-ci-llvm = false in $f"
elif grep -q '^\[llvm\]' "$f" 2>/dev/null; then
	sed -i '/^\[llvm\]/a download-ci-llvm = false' "$f"
	echo "rust-llvm-fix: inserted download-ci-llvm into [llvm] of $f"
else
	printf '\n[llvm]\ndownload-ci-llvm = false\n' >> "$f"
	echo "rust-llvm-fix: appended [llvm] section to $f"
fi
