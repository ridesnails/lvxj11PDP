# Alpine 目录说明

## 目录概述

本目录包含用于在 Alpine Linux 系统上快速安装系统的脚本。适用于 Proxmox VE 等虚拟化环境中的 Alpine 虚拟机。

## 文件说明

### 1. setup-alpine.sh

Alpine Linux 自动安装脚本，用于无人值守安装。

**功能**：
- 自动生成安装应答文件
- 配置键盘布局、主机名、网络、时区等
- 设置 SSH 公钥登录
- 自动分区并安装系统

**使用方法**：
```bash
chmod +x setup-alpine.sh
./setup-alpine.sh
```

**注意**：安装完成后需要重启进入新系统。

## 安装流程

1. **安装 Alpine 系统**
   ```bash
   ./setup-alpine.sh
   # 安装完成后重启
   reboot
   ```

2. **安装 mihomo 服务**
   请参考 `../Mihomo` 目录的说明

## 系统要求

- Alpine Linux 3.23+
- Root 权限
- 网络连接

## 相关链接

- [Alpine Linux](https://alpinelinux.org/)
