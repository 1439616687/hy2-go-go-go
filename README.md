# hy2-go-go-go

Hysteria 2 交互式一键部署脚本：执行后逐步引导你填写信息、自动完成检查与部署，最后输出可直接导入客户端的订阅链接。

基于 [Hysteria 2 官方安装脚本](https://get.hy2.sh/) 与官方文档方案，脚本只负责"引导 + 检查 + 组装"，核心安装由官方脚本完成。

## 一键开始

VPS 上以 root 执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/1439616687/hy2-go-go-go/main/hy2.sh)
```

先完整预演一遍、不改系统（推荐第一次使用）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/1439616687/hy2-go-go-go/main/hy2.sh) --dry-run
```

脚本交互从 `/dev/tty` 读取，通过管道执行也能正常对话。

## 脚本会做什么

1. **安装依赖**：`curl` / `dnsutils` / `ufw` / `openssl` / `ca-certificates`
2. **公网 IP 自检**：获取本机公网 IPv4
3. **引导填写信息**（逐项解释、逐项校验）：
   - 域名 —— 自动核对 A 记录是否指向本机；未指向、无记录或检测到 AAAA/CDN 风险时会明确警告
   - ACME 邮箱、连接密码（可一键随机生成）
   - 服务器带宽（可选，启用 Brutal 拥塞控制）
   - QUIC 窗口调优（可选）
   - Salamander 混淆（可选）
   - 伪装站点 URL、节点名称
4. **安装核心**：调用官方脚本安装/升级 Hysteria 2（systemd 单元自带 `CAP_NET_BIND_SERVICE`，无需 setcap）
5. **写入配置** `/etc/hysteria/config.yaml`（旧配置自动备份；`listen 0.0.0.0:443` + ACME + 密码认证 + 伪装代理）
6. **UFW 防火墙**：先放行探测到的 SSH 端口防止断连，再放行 `443/udp`、`80/tcp`，然后启用
7. **启动并验证**：`systemctl enable --now`，检查服务状态与 UDP/443 监听，失败时自动打印日志
8. **输出订阅链接**：`hy2://` 单节点链接（密码/中文节点名自动 URL 编码），同时保存到 `/etc/hysteria/node.txt`（权限 600）

## 部署前你需要准备

- 一台 Debian / Ubuntu（systemd）VPS，公网 IPv4，root 权限
- 一个域名，A 记录指向 VPS，**不要开 CDN 代理**（如 Cloudflare 橙云需改为「仅 DNS」）
- 云厂商安全组/防火墙（阿里云、AWS、Oracle 等）在控制台放行 `443/udp` 与 `80/tcp`——脚本里的 UFW 替代不了这一步

## 部署后

- 链接导入 v2rayN / NekoBox / sing-box / Streisand 等客户端即可；证书由 ACME 签发，无需开启 `insecure`
- 若部署时填写了带宽，客户端中也填相同上下行，否则 Brutal 不生效
- 输出的是单节点链接，不是订阅；多节点订阅需另搭订阅转换器

维护命令：

```bash
systemctl status hysteria-server.service   # 查看状态
journalctl -u hysteria-server.service -f   # 实时日志
systemctl restart hysteria-server.service  # 改配置后重启
cat /etc/hysteria/node.txt                 # 重新查看订阅链接
```

重新部署/改配置：直接再跑一次脚本即可，旧配置会自动备份。

卸载核心：

```bash
bash <(curl -fsSL https://get.hy2.sh/) --remove
```

## 支持范围

- Debian 11+ / Ubuntu 20.04+（systemd）
- 公网 IPv4（仅监听 IPv4）
- 单实例 `hysteria-server.service`
