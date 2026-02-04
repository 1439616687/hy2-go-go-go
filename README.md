# Hysteria 2 一键安装脚本

适用于 Debian / Ubuntu 系统的 Hysteria 2 服务端一键部署脚本。

## 使用方法

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/1439616687/hy2-go-go-go/main/hy2-install.sh)
```

## 安装前准备

1. 一台 VPS 服务器（Debian / Ubuntu）
2. 一个域名，已解析到服务器 IP
3. Cloudflare 代理已关闭（仅 DNS）
4. 以 root 用户登录

## 常用命令

```bash
# 查看服务状态
systemctl status hysteria-server

# 查看实时日志
journalctl -u hysteria-server -f

# 重启服务
systemctl restart hysteria-server

# 停止服务
systemctl stop hysteria-server

# 编辑配置文件
nano /etc/hysteria/config.yaml

# 查看安装信息
cat /root/hysteria2-info.txt
```

## 更新 Hysteria 2

```bash
bash <(curl -fsSL https://get.hy2.sh/)
systemctl restart hysteria-server
```

## 卸载

重新运行安装脚本，选择「卸载 Hysteria 2」选项。
