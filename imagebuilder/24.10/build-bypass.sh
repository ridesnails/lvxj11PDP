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

# 官方源掉线，临时更换为镜像源
sed -e 's,https://downloads.immortalwrt.org,https://mirror.nju.edu.cn/immortalwrt,g' \
    -e 's,https://mirrors.vsean.net/openwrt,https://mirror.nju.edu.cn/immortalwrt,g' \
    -i.bak ./repositories.conf

# 必装软件包
PACKAGES="curl openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-firewall-zh-cn"
# 推荐软件包
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 安装代理应用
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"

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
PACKAGES="$PACKAGES luci-i18n-nikki-zh-cn"

# 开始生成镜像
make V=s image PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE="800"
