#!/bin/bash
# for 24.10

# 不生成ext4文件系统镜像
# sed -i '/^CONFIG_TARGET_ROOTFS_EXT4FS/d' .config
# 不生成传统启动镜像
sed -i '/^CONFIG_GRUB_IMAGES/d' .config

# 取消生成不需要的打包格式
sed -i '/^CONFIG_ISO_IMAGES/d' .config
sed -i '/^CONFIG_VDI_IMAGES/d' .config
sed -i '/^CONFIG_VMDK_IMAGES/d' .config
sed -i '/^CONFIG_VHDX_IMAGES/d' .config

# 更换为镜像源
sed -i 's|https://downloads.openwrt.org|https://mirrors.ustc.edu.cn/openwrt|g' repositories.conf
# 配置并安装nikki
ARCH="x86_64"
BRANCH="openwrt-24.10"
REPOSITORY_URL="https://nikkinikki.pages.dev"
FEED_URL="$REPOSITORY_URL/$BRANCH/$ARCH/nikki"
echo "添加软件源到 repositories.conf..."
sed -i '/nikki/d' repositories.conf
echo "src/gz nikki $FEED_URL" >> repositories.conf
echo "处理密钥..."
mkdir -p keys
wget -O "keys/ab017c88aab7a08b" "$REPOSITORY_URL/key-build.pub"
echo "完成！现在可以安装nikki软件包了。"

# 自定义软件包
PACKAGES="-dnsmasq dnsmasq-full ip-full openssh-sftp-server qemu-ga \
kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-sched kmod-tcp-bbr \
ca-bundle ca-certificates \
curl wget-ssl jq unzip tree \
htop iftop tcpdump-mini \
luci luci-compat luci-base luci-i18n-base-zh-cn \
luci-i18n-package-manager-zh-cn \
luci-app-firewall luci-i18n-firewall-zh-cn \
luci-app-ttyd luci-i18n-ttyd-zh-cn \
luci-app-nikki luci-i18n-nikki-zh-cn"

# 开始生成镜像
make V=s image PACKAGES="$PACKAGES" FILES=/builder/files BIN_DIR=/output ROOTFS_PARTSIZE="800"
