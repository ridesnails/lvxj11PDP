# Alpine 目录说明

## 目录概述

本目录包含用于在 Alpine Linux 系统上快速部署旁路网关和 mihomo 代理服务的脚本和配置文件。适用于 Proxmox VE 等虚拟化环境中的 Alpine 虚拟机。

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

### 2. install-mihomo-alpine.sh

Alpine 系统 mihomo 旁路网关一键安装脚本。

**主要功能**：
- 系统更新和必要工具安装（含 qemu-guest-agent）
- 自动检测系统架构和 CPU 指令集
- 下载匹配架构的 mihomo 最新版本
- 配置 nftables 防火墙（支持 IPv4/IPv6）
- 配置系统网络参数（开启 IP 转发、BBR 等）
- 创建 mihomo 配置目录和默认配置
- 创建 OpenRC 服务并设置开机启动
- 配置日志轮转

**防火墙规则**：
- 允许本地回环流量
- 允许已建立连接
- 丢弃无效连接
- 放行所有 ICMPv6
- 允许本地私网网段（IPv4/IPv6）

**使用方法**：
```bash
chmod +x install-mihomo-alpine.sh
./install-mihomo-alpine.sh
```

### 3. update-ipv6-set

动态更新 IPv6 直连网段到防火墙规则。

**功能**：
- 自动检测主网卡
- 提取以 2 开头的 IPv6 前缀（通常是公网地址）
- 添加到 nftables 集合，设置 2 小时超时
- 支持重复执行刷新超时时间

**使用方法**：
```bash
chmod +x update-ipv6-set
./update-ipv6-set
```

**建议**：配合 crontab 定期执行（如每 15 分钟）：
```bash
echo '*/15 * * * * /etc/periodic/15min/update-ipv6-set' | crontab -
```

### 4. config.yaml

mihomo 配置文件示例（简化版）。

**特点**：
- 仅包含最基本配置
- 混合端口 7890
- 外部控制器 9090 端口
- 启用 DNS
- 空代理列表（需自行添加）

## 安装流程

1. **安装 Alpine 系统**
   ```bash
   ./setup-alpine.sh
   # 安装完成后重启
   reboot
   ```

2. **安装 mihomo 服务**
   ```bash
   ./install-mihomo-alpine.sh
   ```

3. **配置 IPv6 动态更新**（可选）
   ```bash
   mkdir -p /etc/periodic/15min
   cp update-ipv6-set /etc/periodic/15min/
   chmod +x /etc/periodic/15min/update-ipv6-set
   ```

4. **配置 mihomo**
   - 编辑 `/etc/mihomo/config.yaml`
   - 添加代理服务器
   - 重启服务：`rc-service mihomo restart`

## 服务管理

```bash
# 查看服务状态
rc-service mihomo status
rc-service nftables status
rc-service qemu-guest-agent status

# 启动/停止/重启
rc-service mihomo start
rc-service mihomo stop
rc-service mihomo restart

# 查看日志
tail -f /var/log/mihomo/mihomo.log
```

## Web 面板

安装完成后访问：
```
http://<服务器IP>:9090
```

## 系统要求

- Alpine Linux 3.23+
- 支持 TUN 的内核
- Root 权限
- 网络连接

## 故障排查

| 问题 | 排查命令 |
|------|----------|
| mihomo 无法启动 | `tail /var/log/mihomo/mihomo.log` |
| 防火墙规则 | `nft list ruleset` |
| TUN 模块 | `lsmod \| grep tun` |
| 网络连接 | `ping -c 4 223.5.5.5` |
| IPv6 网段 | `ip -6 route show` |

## 相关链接

- [mihomo](https://github.com/MetaCubeX/mihomo)
- [Alpine Linux](https://alpinelinux.org/)
