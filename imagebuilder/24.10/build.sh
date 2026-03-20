#!/bin/bash
# for 24.10

# 不生成ext4文件系统镜像
sed -i '/^CONFIG_TARGET_ROOTFS_EXT4FS/d' .config
# 不生成传统启动镜像
sed -i '/^CONFIG_GRUB_IMAGES/d' .config

# 取消生成不需要的打包格式
sed -i '/^CONFIG_ISO_IMAGES/d' .config
sed -i '/^CONFIG_VDI_IMAGES/d' .config
sed -i '/^CONFIG_VMDK_IMAGES/d' .config
sed -i '/^CONFIG_VHDX_IMAGES/d' .config

# 必装软件包
PACKAGES="curl openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-firewall-zh-cn"
# 推荐软件包
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 推荐主题包
PACKAGES="$PACKAGES luci-app-argon-config luci-i18n-argon-config-zh-cn"

# 开始生成镜像
make V=s image PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE="800"
