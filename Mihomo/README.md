# Mihomo 目录说明

本目录存储 mihomo 代理工具的自定义配置文件。

## 文件说明

### config.yaml

mihomo 完整配置文件示例，包含丰富的代理规则和分流策略。

## 配置特点

### 网络设置
- 混合端口：7892（支持 HTTP/HTTPS/SOCKS）
- 外部控制器：`[::]:9090`（IPv4/IPv6 双栈）
- 允许局域网访问
- 启用 TUN 模式（设备 tun0）
- 支持 IPv6

### DNS 配置
- 启用 DNS 服务，监听 53 端口
- 增强模式：redir-host
- 支持 Fake-IP
- 国内 DNS：阿里 DNS、腾讯 DNS
- 国外 DNS：Google DNS、Cloudflare DNS（通过代理）

### 代理组策略

| 代理组 | 类型 | 说明 |
|--------|------|------|
| 🚀 默认代理 | select | 主代理选择 |
| 🤖 ChatGPT | select | AI 服务专用 |
| 🎵 TikTok | select | 流媒体服务 |
| 🎯 直连 | select | 直连流量 |
| 🐟 漏网之鱼 | select | 默认匹配 |
| 🇭🇰 香港节点 | select | 香港地区节点 |
| 🔯 香港故转 | fallback | 香港故障转移 |
| ♻️ 香港自动 | url-test | 香港自动选择 |
| 🌏 亚洲节点 | select | 亚洲地区节点 |
| 🔯 亚洲故转 | fallback | 亚洲故障转移 |
| ♻️ 亚洲自动 | url-test | 亚洲自动选择 |
| 🇺🇲 美国节点 | select | 美国地区节点 |
| 🔯 美国故转 | fallback | 美国故障转移 |
| ♻️ 自动选择 | url-test | 全局自动选择 |
| 🌐 全部节点 | select | 所有节点 |

### 规则集

**域名规则**：
- AI 服务（ChatGPT 等）
- TikTok
- Google（含 YouTube）
- GitHub
- Telegram
- GFW 列表

**IP 规则**：
- Google IP
- Telegram IP
- Netflix IP
- 中国 IP

**自定义规则**：
- 直连域名：Syncthing、Cloudreve
- 代理域名：七尺宇博客、TMDb API

### 代理提供商

使用环境变量 `HONGXING_URL` 加载订阅：
```yaml
proxy-providers:
  红杏:
    type: http
    url: "$env(HONGXING_URL)"
```

## 使用方法

1. **设置环境变量**
   ```bash
   export HONGXING_URL="你的订阅链接"
   ```

2. **复制配置文件**
   ```bash
   cp config.yaml /etc/mihomo/config.yaml
   ```

3. **重启 mihomo**
   ```bash
   rc-service mihomo restart
   ```

## 自定义规则

编辑 `config.yaml` 中的 `rule-providers` 和 `rules` 部分：

```yaml
rule-providers:
  my_rules:
    type: http
    behavior: domain
    url: "https://example.com/my-rules.txt"
    interval: 86400

rules:
  - RULE-SET,my_rules,🎯 直连
```

## 注意事项

1. 订阅链接通过环境变量传入，避免硬编码敏感信息
2. 规则集使用 MRS 格式，加载更快
3. 定期自动更新 GeoIP/GeoSite 数据
4. 启用 TUN 模式需要系统支持

## 相关链接

- [mihomo 文档](https://wiki.metacubex.one/)
- [MetaCubeX 规则数据](https://github.com/MetaCubeX/meta-rules-dat)
