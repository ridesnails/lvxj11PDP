# Mihomo 目录说明

## 目录概述

本目录包含用于在 Alpine Linux 系统上快速部署 mihomo 代理服务的脚本和配置文件。适用于已安装好的 Alpine 系统。

## 文件说明

### 1. install-mihomo-alpine.sh

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

### 2. assets/config.yaml

mihomo 完整配置文件，包含丰富的功能配置。

**主要功能**：
- 代理提供商自动更新（支持环境变量配置）
- 详细的 DNS 配置（DoH、fake-ip、域名策略等）
- 丰富的代理组（香港、亚洲、美国节点等多种选择）
- 完整的规则配置（AI、TikTok、GitHub、Google、YouTube、Telegram等）
- TUN 模式配置（自动路由、自动重定向、大 MTU）
- Sniffer 协议检测（HTTP、TLS、QUIC）
- 认证配置
- 外部 UI 支持（Zashboard）
- 地理位置数据自动更新

**注意**：需根据实际情况修改 `PROVIDER1_URL` 环境变量或直接配置代理服务器。

### 3. assets/sysctl.conf.template

系统网络参数优化配置模板。

**主要配置**：
- IP 转发（IPv4/IPv6）
- IPv6 RA 接收（旁路网关关键）
- 禁止重定向（防止路由冲突）
- TCP 拥塞控制（BBR + fq）
- 连接跟踪优化
- 网络队列和缓冲区调优
- 安全加固

**应用方式**：由 `install-mihomo-alpine.sh` 自动部署到 `/etc/sysctl.d/99-network-gateway.conf`

### 4. assets/network-optimization

网卡硬件层优化脚本（hotplug）。

**主要功能**：
- 增大发送队列长度（txqueuelen = 5000）
- 启用硬件卸载（TSO/GSO/GRO/LRO）
- 自动配置多队列（根据 CPU 核心数）

**与 sysctl 的区别**：
- sysctl：内核协议栈层参数，持久化配置
- network-optimization：网卡驱动层参数，需要 hotplug 脚本

**部署方式**：复制到 `/etc/network/if-up.d/` 目录，每次网卡启动时自动执行

### 5. assets/nftables.conf

nftables 防火墙规则配置。

**规则说明**：
- 允许本地回环流量
- 允许已建立连接
- 丢弃无效连接
- 放行所有 ICMPv6
- 允许本地私网网段（IPv4/IPv6）

### 6. assets/radvd.conf.template

IPv6 路由通告服务配置模板。

**功能**：向局域网广播 IPv6 前缀，实现 IPv6 旁路网关

### 7. assets/mihomo-service

mihomo OpenRC 服务脚本。

**功能**：
- 启动/停止 mihomo 进程
- 支持 reload 配置
- 状态检查

### 8. assets/logrotate.conf.template

mihomo 日志轮转配置。

**功能**：
- 日志大小限制（100MB）
- 保留 10 个历史文件
- 自动压缩旧日志

### 9. assets/update-ipv6-set

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

## 安装流程

1. **安装 Alpine 系统**
   请参考 `../Alpine` 目录的说明

2. **安装 mihomo 服务**
   ```bash
   chmod +x install-mihomo-alpine.sh
   ./install-mihomo-alpine.sh
   ```

3. **配置 IPv6 动态更新**（可选）
   ```bash
   mkdir -p /etc/periodic/15min
   cp assets/update-ipv6-set /etc/periodic/15min/
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
rc-service radvd status

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
| TUN 模块 | `lsmod | grep tun` |
| 网络连接 | `ping -c 4 223.5.5.5` |
| IPv6 网段 | `ip -6 route show` |

## 相关链接

- [mihomo](https://github.com/MetaCubeX/mihomo)
- [Alpine Linux](https://alpinelinux.org/)