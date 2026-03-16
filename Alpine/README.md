# Alpine 目录说明

## 目录概述

Alpine 目录包含了用于在 Alpine Linux 系统上部署和配置 mihomo 代理服务的相关文件和脚本。这些文件旨在帮助用户快速搭建一个功能完整的网络代理环境，支持 IPv4 和 IPv6，并提供了丰富的代理规则和配置选项。

## 文件说明

### 1. setup-alpine.sh

**功能**：Alpine Linux 自动安装脚本

**主要内容**：
- 生成 `answers.txt` 文件，包含安装配置选项
- 执行 Alpine Linux 安装过程
- 配置 SSH 允许 root 公钥登录

**使用方法**：
```bash
chmod +x setup-alpine.sh
./setup-alpine.sh
```

### 2. install-mihomo-alpine.sh

**功能**：Alpine 3.23 旁路网关 + mihomo 一键安装脚本

**主要功能**：
- 检查内核版本兼容性
- 检测主网卡名称
- 获取系统架构
- 更新系统并安装必要工具
- 设置时区
- 加载 TUN 内核模块
- 配置 nftables 防火墙
- 配置系统网络参数
- 下载并安装最新版本的 mihomo
- 创建配置目录和默认配置
- 创建 OpenRC 服务
- 配置并启动服务

**使用方法**：
```bash
chmod +x install-mihomo-alpine.sh
./install-mihomo-alpine.sh
```

### 3. update-ipv6-set

**功能**：动态更新 IPv6 网段到 nftables 防火墙规则

**主要功能**：
- 动态检测主网卡
- 提取以 2 开头的 IPv6 直连网段
- 将网段添加到 nftables 的 local_ipv6_list 集合中，设置 2 小时超时

**使用方法**：
```bash
chmod +x update-ipv6-set
./update-ipv6-set
```

### 4. config.yaml

**功能**：mihomo 详细配置文件

**主要配置项**：
- 网络设置（允许局域网访问、绑定地址等）
- DNS 配置（启用 IPv6、增强模式、DNS 服务器等）
- 代理设置（直连代理）
- 代理组配置（默认代理、ChatGPT、TikTok、直连、漏网之鱼等）
- 代理提供商配置
- 规则配置（禁用 QUIC、域名规则、IP 规则等）
- 规则提供商配置（AI、TikTok、Google、GitHub、YouTube、Telegram、GFW 等）
- TUN 配置（启用 TUN、设备设置、路由配置等）
- Sniffer 配置（启用流量嗅探）
- 其他高级设置（认证、Geo 数据更新等）

## 系统要求

- Alpine Linux 3.23 或更高版本
- 支持 TUN 内核模块
- 网络连接
- Root 权限

## 安装流程

1. 首先运行 `setup-alpine.sh` 安装 Alpine Linux 系统
2. 系统安装完成后，运行 `install-mihomo-alpine.sh` 安装并配置 mihomo 代理服务
3. 根据需要运行 `update-ipv6-set` 更新 IPv6 网段规则
4. 根据实际网络环境修改 `config.yaml` 配置文件

## 管理命令

- 启动 mihomo 服务：`rc-service mihomo start`
- 停止 mihomo 服务：`rc-service mihomo stop`
- 重启 mihomo 服务：`rc-service mihomo restart`
- 查看 mihomo 服务状态：`rc-service mihomo status`

## Web UI 访问

安装完成后，可以通过以下地址访问 mihomo 的 Web 管理界面：

```
http://<服务器IP>:9090/ui
```

默认认证信息：
- 用户名：lvxj11
- 密码：0129

## 注意事项

1. 安装前请确保系统满足要求
2. 安装过程中需要网络连接以下载必要的软件包和 mihomo 二进制文件
3. 请根据实际网络环境修改 `config.yaml` 中的代理配置
4. 如需添加自定义代理，请在 `config.yaml` 的 `proxies` 部分添加
5. 定期运行 `update-ipv6-set` 脚本更新 IPv6 网段规则

## 故障排查

- 查看 mihomo 日志：`tail -f /var/log/mihomo/mihomo.log`
- 检查网络连接：`ping -c 4 google.com`
- 检查 TUN 模块：`lsmod | grep tun`
- 检查 nftables 规则：`nft list ruleset`

## 相关链接

- [mihomo 项目](https://github.com/MetaCubeX/mihomo)
- [Alpine Linux 官方网站](https://alpinelinux.org/)
- [MetaCubeX 规则数据](https://github.com/MetaCubeX/meta-rules-dat)