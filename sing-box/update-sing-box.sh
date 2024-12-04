#!/bin/sh

# 设置变量
REPO="SagerNet/sing-box"        # GitHub 仓库名
VERSION_PREFIX="v1.11"           # 指定主版本号
ARCH="linux-amd64"              # 指定系统架构
DOWNLOAD_DIR="./downloads"      # 下载目录
EXTRACT_DIR="./extracted"       # 解压目录
TARGET_DIR="/usr/bin"           # 目标目录

# 创建目录
mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"

# 获取 GitHub Releases 的所有资产列表
API_URL="https://api.github.com/repos/$REPO/releases"

ASSET_URL=$(curl -s "$API_URL" | jq -r \
  --arg version_prefix "$VERSION_PREFIX" \
  --arg arch "$ARCH" \
  '.[] | select(.tag_name | startswith($version_prefix)) | .assets[] | select(.name | endswith($arch + ".tar.gz")) | .browser_download_url' | head -n 1)

# 检查是否找到匹配的资产
if [ -z "$ASSET_URL" ]; then
  echo "未找到符合条件的版本！请检查版本号或系统架构。"
  exit 1
fi

# 提取文件名
FILENAME=$(basename "$ASSET_URL")

# 下载文件
echo "正在下载：$FILENAME"
curl -L -o "$DOWNLOAD_DIR/$FILENAME" "https://mirror.ghproxy.com/$ASSET_URL"

# 检查下载是否成功
if [ $? -ne 0 ]; then
  echo "下载失败！"
  exit 1
fi

# 解压文件
echo "正在解压到：$EXTRACT_DIR"
tar -xzvf "$DOWNLOAD_DIR/$FILENAME" -C "$EXTRACT_DIR"

# 检查解压是否成功
if [ $? -ne 0 ]; then
  echo "解压失败！"
  exit 1
fi

# 查找解压目录中的 `sing-box` 文件
SING_BOX_PATH=$(find "$EXTRACT_DIR" -type f -name "sing-box")

if [ -z "$SING_BOX_PATH" ]; then
  echo "未找到 sing-box 文件！"
  exit 1
fi

# 复制到 /usr/bin 并覆盖
echo "复制 sing-box 到 $TARGET_DIR"
cp "$SING_BOX_PATH" "$TARGET_DIR/sing-box"

# 确保文件有执行权限
chmod +x "$TARGET_DIR/sing-box"

echo "sing-box 已成功更新到 $TARGET_DIR"
