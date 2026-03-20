#!/bin/bash
# for 25.12

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
# sed -i 's|https://downloads.openwrt.org|https://mirrors.ustc.edu.cn/openwrt|g' repositories
# 添加nikki源
ARCH="x86_64"
BRANCH="openwrt-25.12"
REPOSITORY_URL="https://nikkinikki.pages.dev"
FEED_URL="$REPOSITORY_URL/$BRANCH/$ARCH/nikki"
echo "添加密钥..."
mkdir -p keys
wget -O "keys/nikki.pem" "$REPOSITORY_URL/public-key.pem"
echo "添加软件源到 repositories..."
sed -i '/nikki/d' repositories
echo "$FEED_URL/packages.adb" >> repositories
echo "完成！现在可以安装nikki软件包了。"

# 自定义软件包
PACKAGES="-dnsmasq dnsmasq-full ip-full \
kmod-tun kmod-inet-diag kmod-nft-tproxy \
ca-bundle curl wget-ssl unzip tree \
htop iftop tcpdump-mini \
openssh-sftp-server qemu-ga \
luci luci-compat luci-base luci-i18n-base-zh-cn \
luci-i18n-package-manager-zh-cn \
luci-app-firewall luci-i18n-firewall-zh-cn \
luci-app-ttyd luci-i18n-ttyd-zh-cn \
luci-app-upnp luci-i18n-upnp-zh-cn \
luci-app-nikki luci-i18n-nikki-zh-cn"

# 开始生成镜像
make V=s image PACKAGES="$PACKAGES" FILES=/builder/files BIN_DIR=/output ROOTFS_PARTSIZE="800"
