# 京东云亚瑟 AX1800 Pro（RE-SS-01）GitHub 云编译定制固件

面向 **京东云无线宝 AX1800 Pro（代号「亚瑟」，型号 RE-SS-01，IPQ6000，512MB 内存，64GB eMMC）** 的 GitHub Actions 云编译工程。

- 源码：`VIKINGYFY/immortalwrt`（`owrt` 分支，上游活跃分支），高通闭源 QCA WiFi 驱动版（`IPQ60XX-WIFI-YES`）
- 目标设备：`qualcommax/ipq60xx/jdcloud_re-ss-01`（只编译这一个设备）
- 默认 LAN：`192.168.68.1`（与京东云原厂/QWRT 默认一致）
- 默认主机名：`JDC-AX1800Pro`，默认主题：Argon + Kucat，中文 LuCI
- 云编译框架：改编自 [Jovi-cmyk/Bailangvvk_AX1800Pro](https://github.com/Jovi-cmyk/Bailangvvk_AX1800Pro)

## 目录结构

```
.github/workflows/QCA-ALL.yml   # 手动触发入口（改默认 IP/主机名/WiFi 名在这里）
.github/workflows/WRT-CORE.yml  # 编译核心（克隆源码、加插件、出固件、发 Release）
Config/IPQ60XX-WIFI-YES.txt     # 只勾选 jdcloud_re-ss-01
Config/GENERAL.txt              # 插件/内核/参数清单（加插件改这里）
Scripts/Settings.sh             # 默认值 sed + 追加配置（追加的配置在 .config 末尾，最后生效）
Scripts/Packages.sh             # 拉取第三方插件源（homeproxy/openclash/passwall/kucat/...）
Scripts/Handles.sh              # 预置规则数据（homeproxy 规则、OpenClash 内核）
```

## 云编译使用步骤

1. GitHub 新建一个**公开**空仓库，例如 `jdcloud-ax1800pro-openwrt`。
2. 把本目录所有文件推送到仓库默认分支（必须保留 `.github/`、`Config/`、`Scripts/`）：

   ```bash
   cd repo
   git init -b main
   git add .
   git commit -m "jdcloud ax1800 pro ci"
   git remote add origin https://github.com/<你的用户名>/jdcloud-ax1800pro-openwrt.git
   git push -u origin main
   ```

3. 打开仓库 **Actions → QCA-ALL → Run workflow**。
   - 第一次先保持 `TEST = true` 跑一遍：只生成 `.config`（在产物 `Config_IPQ60XX-WIFI-YES_*.txt` 里），确认插件都编进去了、没有大片 `missing` 再正式编。
   - 正式编译：`TEST = false`，全程约 1~2 小时。
4. 编译成功后在仓库 **Releases** 下载固件，认准文件名里带 `re-ss-01` 和 `squashfs-sysupgrade` 的那个。
   - 同时下载 Release 里的 `Config_*.txt`，那是本次编译的完整 `.config`，可用于复现。
5. 需要临时加一个插件时，用 workflow 的 `PACKAGE` 输入框，格式 `CONFIG_PACKAGE_xxx=y`（仅限一个，多行会挤掉）。

## 相对上游的定制点

| 项 | 说明 |
|---|---|
| LAN 地址 | `192.168.10.1` → `192.168.68.1`，刷完和原来一样 |
| 主机名 / WiFi 名 | `JDC-AX1800Pro`（闭源 QCA 驱动下 WiFi 改名不一定生效，以实机为准） |
| 增加插件生效 | 上游 `Settings.sh` 会强行 `=n` 剔除 wolplus/tailscale/advancedplus/kucat，与 `GENERAL.txt` 的“增加插件”打架；本仓库把这 4 行注释掉，以 `GENERAL.txt` 为准 |
| 内存档位 | 追加 `CONFIG_IPQ_MEM_PROFILE_512=y` 等 4 行，锁定 512MB（上游 README 标注必须） |
| `advancedplus` | 源码拉取在 `Packages.sh` 里被上游注释（与官方 Argon 主题不兼容）；`GENERAL.txt` 里的 `=y` 若包不存在会被 defconfig 自动丢弃，不报错。想用就自己取消注释 |

## 插件清单（Config/GENERAL.txt + Settings.sh 合并结果）

- 科学上网：homeproxy（含预置规则）、passwall、openclash（含内核）、ssr-plus、mihomo/nekoclash
- 网络：smartdns、adguardhome、turboacc + BBR、kmod-tun、XDP/BPF 全套、NFS、samba4、aria2、docker（dockerman）（alist 因 cgofuse/fuse.h 交叉编译问题暂移除）
- 运维：btop、jq、curl、htop、iperf3、openssh-sftp-server、autoreboot、WOL（wolplus）、tailscale、kucat 主题
- 内核模块：fuse、tun、wireguard kmod、mtd-rw、全套 USB 网卡/存储驱动（USB3 移动硬盘可用）
- 已剔除：wol、ddns、vlmcsd、xlnetacc、zerotier、luci-app-wireguard、ipsec-vpnd、adbyby-plus、filetransfer、unblockmusic、accesscontrol、fileassistant

> NSS 相关 feed 在 IPQ 平台被主动关闭（`Settings.sh`），本固件走 VIKINGYFY 自带的开源硬件加速路径。

## 刷机（从当前 QWRT R25.05.01 迁移）

> 板名不同：QWRT 的板名是 `jdcloud_ax1800-pro`，本固件板名是 `jdcloud_re-ss-01`，**首次迁移绝对不能保留配置**，sysupgrade 校验会拒绝，需要强制。

1. 后台/SSH 备份当前配置（LuCI → 系统 → 备份/升级 → 生成备份），SSH 入口一般还是 `root@192.168.68.1`。
2. 把 `*-squashfs-sysupgrade.bin` 传到路由器 `/tmp/`（LuCI 上传或 `scp`）。
3. 刷写（二选一）：
   - LuCI：系统 → 备份/升级 → 刷新固件 → **取消勾选“保留配置”** → 提示镜像不符时选**强制**。
   - SSH：
     ```sh
     sysupgrade -n -F /tmp/*re-ss-01*squashfs-sysupgrade.bin
     ```
4. 等 2~3 分钟重启，访问 `http://192.168.68.1`，首次启动会要求设置 root 密码。
5. 万一起不来：走 U-Boot Web 免拆救砖，首次只上传 `*-squashfs-recovery.bin`（参考 [WorldHim/jdc-ax1800pro-openwrt](https://github.com/WorldHim/jdc-ax1800pro-openwrt) 教程，注意其 U-Boot 按 6MiB 切分，不能传 sysupgrade/factory）。

## 本地编译（可选）

Ubuntu 22.04/24.04，不要用 root：

```bash
sudo apt update -y && sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib \
  git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev \
  libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev libssl-dev libtool lrzsz \
  nano ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip libpython3-dev qemu-utils \
  rsync scons squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev

git clone https://github.com/VIKINGYFY/immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
# 应用本仓库的配置（相当于云编译做的事）
cat /path/to/this/repo/Config/IPQ60XX-WIFI-YES.txt /path/to/this/repo/Config/GENERAL.txt >> .config
make defconfig
make download -j$(nproc) && make -j$(nproc)
```

产物在 `bin/targets/qualcommax/ipq60xx/`。
