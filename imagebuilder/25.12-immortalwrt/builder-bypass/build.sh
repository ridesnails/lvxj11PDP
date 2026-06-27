#!/bin/bash
# for ImmortalWrt 25.12 (Docker环境)

set -e

echo "=== ImmortalWrt ImageBuilder 构建脚本 ==="
echo "当前目录: $(pwd)"
echo "Docker环境: $(hostname)"

# 确保在正确的目录
if [ ! -f Makefile ]; then
    echo "错误: 未找到 Makefile，请确认脚本所在目录为 ImageBuilder 目录"
    exit 1
fi

# 不生成ext4文件系统镜像
# sed -i '/^CONFIG_TARGET_ROOTFS_EXT4FS/d' .config
# 不生成传统启动镜像
sed -i '/^CONFIG_GRUB_IMAGES/d' .config

# 取消生成不需要的打包格式
sed -i '/^CONFIG_ISO_IMAGES/d' .config
sed -i '/^CONFIG_VDI_IMAGES/d' .config
sed -i '/^CONFIG_VMDK_IMAGES/d' .config
sed -i '/^CONFIG_VHDX_IMAGES/d' .config

# 更换为国内镜像源（将 ImmortalWrt 官方源替换为浙大镜像，加速下载）
sed -i 's|https://downloads.immortalwrt.org|https://mirror.zju.edu.cn/immortalwrt|g' repositories

# 自定义软件包
PACKAGES="-dnsmasq dnsmasq-full ip-full openssh-sftp-server qemu-ga \
kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-sched kmod-tcp-bbr \
ca-bundle ca-certificates \
curl wget-ssl jq unzip tree \
htop iftop tcpdump-mini \
luci luci-compat luci-base luci-i18n-base-zh-cn \
luci-i18n-package-manager-zh-cn \
luci-app-firewall luci-i18n-firewall-zh-cn \
luci-app-ttyd luci-i18n-ttyd-zh-cn"

# 添加nikki源（ImmortalWrt兼容）
ARCH="x86_64"
BRANCH="openwrt-25.12"
REPOSITORY_URL="https://nikkinikki.pages.dev"
FEED_URL="$REPOSITORY_URL/$BRANCH/$ARCH/nikki"
echo "添加密钥..."
mkdir -p keys
wget -O "keys/nikki.pem" "$REPOSITORY_URL/public-key.pem" || echo "警告: nikki密钥下载失败，跳过添加"
echo "添加软件源到 repositories..."
sed -i '/nikki/d' repositories
if [ -f "keys/nikki.pem" ]; then
    echo "$FEED_URL/packages.adb" >> repositories
    echo "完成！nikki软件源已添加。"
    PACKAGES="$PACKAGES luci-app-nikki luci-i18n-nikki-zh-cn"
else
    echo "警告: nikki软件源未添加"
fi

# 开始生成镜像（使用相对路径，适配非Docker环境）
make V=s image PACKAGES="$PACKAGES" FILES=/builder/files BIN_DIR=/output ROOTFS_PARTSIZE="800"
