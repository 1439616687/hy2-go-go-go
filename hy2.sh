#!/usr/bin/env bash
#
# hy2.sh — Hysteria 2 交互式一键部署脚本
# https://github.com/1439616687/hy2-go-go-go
#
# 用法：
#   bash hy2.sh             交互式部署
#   bash hy2.sh --dry-run   预演：完整走一遍交互与检查，但不修改系统
#
set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.1"
readonly HY2_DIR="/etc/hysteria"
readonly HY2_CONFIG="${HY2_DIR}/config.yaml"
readonly NODE_INFO="${HY2_DIR}/node.txt"
readonly HY2_SERVICE="hysteria-server.service"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,11p' "$0"
  exit 0
fi

# ---------- 输出 ----------

if [[ -t 1 ]]; then
  C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_B=$'\e[36m' C_0=$'\e[0m'
else
  C_G="" C_Y="" C_R="" C_B="" C_0=""
fi

info() { printf '%s[信息]%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[注意]%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '%s[错误]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s== %s ==%s\n' "$C_G" "$*" "$C_0"; }

# 执行命令；dry-run 下只打印不执行
run() {
  if (( DRY_RUN )); then
    info "[dry-run] $*"
  else
    "$@"
  fi
}

# ---------- 输入 ----------
# 终端直接运行时读 stdin；curl | bash 场景 stdin 被脚本占用，改读 /dev/tty；
# 无 tty（自动化测试）时回落到 stdin。
if [[ -t 0 ]]; then
  HY2_IN=0
elif { : </dev/tty; } 2>/dev/null; then
  exec 9</dev/tty
  HY2_IN=9
else
  HY2_IN=0
fi

# prompt <变量名> <提示语> [默认值]
prompt() {
  local __var="$1" __msg="$2" __def="${3:-}" __ans
  if [[ -n "$__def" ]]; then
    printf '%s?%s %s [%s]: ' "$C_B" "$C_0" "$__msg" "$__def"
  else
    printf '%s?%s %s: ' "$C_B" "$C_0" "$__msg"
  fi
  read -r __ans <&"$HY2_IN" || die "读取输入失败（输入流已结束）"
  [[ -n "$__ans" ]] || __ans="$__def"
  printf -v "$__var" '%s' "$__ans"
}

# confirm <提示语> [默认 y|n]；是返回 0，否返回 1
confirm() {
  local __msg="$1" __def="${2:-n}" __ans __hint
  if [[ "$__def" == "y" ]]; then __hint="Y/n"; else __hint="y/N"; fi
  while true; do
    printf '%s?%s %s [%s]: ' "$C_B" "$C_0" "$__msg" "$__hint"
    read -r __ans <&"$HY2_IN" || die "读取输入失败（输入流已结束）"
    __ans="${__ans:-$__def}"
    case "${__ans,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     warn "请输入 y 或 n" ;;
    esac
  done
}

# ---------- 校验与编码 ----------

valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
valid_email()  { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
valid_ipv4()   { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
valid_mbps()   { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 1000000 )); }
valid_port()   { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

# RFC 3986 URL 编码（链接中的密码/节点名可能含特殊字符或中文）
urlencode() {
  local s="$1" i c out=""
  local LC_ALL=C  # 按字节遍历，保证 UTF-8 多字节字符逐字节编码
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) out+="$c" ;;
      *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# YAML 双引号字符串转义（防止自定义密码破坏配置语法）
yaml_quote() {
  local s="${1//\\/\\\\}"
  printf '"%s"' "${s//\"/\\\"}"
}

# ---------- 0. 前置检查 ----------

clear 2>/dev/null || true
printf '%s' "$C_G"
cat <<'BANNER'
  _                ____                 ____                 ____
 | |__  _   _ ___  / ___| ___   ___     / ___| ___   ___     / ___| ___
 | '_ \| | | / __|| |  _ / _ \ / _ \   | |  _ / _ \ / _ \   | |  _ / _ \
 | | | | |_| \__ \| |_| | (_) | (_) |  | |_| | (_) | (_) |  | |_| | (_) |
 |_| |_|\__, |___/ \____|\___/ \___/    \____|\___/ \___/    \____|\___/
        |___/            Hysteria 2 交互式一键部署
BANNER
printf '%s\n' "$C_0"
info "版本 v${SCRIPT_VERSION} | 项目地址 https://github.com/1439616687/hy2-go-go-go"
if (( DRY_RUN )); then
  warn "当前为 --dry-run 预演模式：只检查与演示，不会修改系统"
fi

(( EUID == 0 )) || die "请使用 root 运行本脚本（或先执行 sudo -i）"

[[ -r /etc/os-release ]] || die "无法识别操作系统"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  debian|ubuntu) ok "系统：${PRETTY_NAME:-$ID}" ;;
  *) die "仅支持 Debian / Ubuntu，检测到：${PRETTY_NAME:-未知}" ;;
esac
command -v apt-get   >/dev/null || die "未找到 apt-get"
command -v systemctl >/dev/null || die "未找到 systemctl，本脚本仅支持 systemd 系统"

# 容器环境检测：OpenVZ/LXC 等与宿主机共享内核，iptables/nftables 常受限，UFW 多半用不了
CONTAINER=0
VIRT="$(systemd-detect-virt 2>/dev/null || true)"
case "$VIRT" in
  openvz|lxc|lxc-libvirt|systemd-nspawn)
    CONTAINER=1
    warn "检测到 ${VIRT} 容器：内核受限，UFW 可能无法启用（失败会自动跳过，不影响部署）"
    ;;
esac

# ---------- 1. 安装依赖 ----------

step "1/7 安装依赖"
run apt-get update -qq
run apt-get install -y curl dnsutils ufw openssl ca-certificates
ok "依赖就绪（curl / dig / ufw / openssl）"

# ---------- 2. 公网 IP 自检 ----------

step "2/7 检测本机公网 IPv4"
PUBIP=""
for url in https://ifconfig.me https://api.ipify.org https://ip.sb; do
  ip="$(curl -4 -fsSL --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$ip" ]] && valid_ipv4 "$ip"; then
    PUBIP="$ip"
    break
  fi
done
[[ -n "$PUBIP" ]] || die "无法获取本机公网 IPv4，请检查网络"
ok "本机公网 IPv4：${PUBIP}"

# ---------- 3. 收集部署信息 ----------

step "3/7 填写部署信息"

info "域名要求：A 记录已指向 ${PUBIP}，且未开启 CDN 代理（如 Cloudflare 橙云，需改为「仅 DNS」）"
while true; do
  prompt DOMAIN "绑定到本机的域名（例如 hy2.example.com）"
  if valid_domain "$DOMAIN"; then break; fi
  warn "域名格式不正确，请重新输入"
done

# DNS 检查：dig 侧与本机侧一致才算“指向本机”
if command -v dig >/dev/null; then
  RESOLVED="$(dig +short A "$DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1 || true)"
  if [[ "$RESOLVED" == "$PUBIP" ]]; then
    ok "DNS 检查通过：${DOMAIN} → ${PUBIP}"
  elif [[ -z "$RESOLVED" ]]; then
    warn "未查询到 ${DOMAIN} 的 A 记录"
    confirm "仍然继续吗（DNS 生效前 ACME 证书签发会失败）？" n || die "已取消，请先配置 DNS 解析"
  else
    warn "${DOMAIN} 当前解析到 ${RESOLVED}，与本机 ${PUBIP} 不一致"
    warn "若开启了 CDN 代理，请切换为「仅 DNS」后再继续"
    confirm "仍然继续吗？" n || die "已取消，请先修正 DNS 解析"
  fi
  AAAA="$(dig +short AAAA "$DOMAIN" @1.1.1.1 2>/dev/null | grep -E ':' | head -1 || true)"
  if [[ -n "$AAAA" ]]; then
    warn "检测到 AAAA 记录（${AAAA}）；本方案仅使用 IPv4，建议删除该记录，避免客户端优先走 IPv6"
  fi
else
  warn "未找到 dig，跳过 DNS 一致性检查"
fi

while true; do
  prompt EMAIL "ACME 注册邮箱（用于证书到期提醒）"
  if valid_email "$EMAIL"; then break; fi
  warn "邮箱格式不正确，请重新输入"
done

GEN_PASS="$(openssl rand -hex 16)"
prompt PASSWORD "连接密码（直接回车使用随机密码）" "$GEN_PASS"
[[ -n "$PASSWORD" ]] || die "密码不能为空"

info "填写服务器实际带宽可启用 Brutal 拥塞控制（高带宽网络下吞吐更好）；不填则使用类 BBR 模式"
SET_BW=0
if confirm "现在填写带宽吗（推荐）" y; then
  SET_BW=1
  while true; do
    prompt BW_UP "服务器上行带宽（Mbps）" "500"
    if valid_mbps "$BW_UP"; then break; fi
    warn "请输入 1-1000000 之间的整数"
  done
  while true; do
    prompt BW_DOWN "服务器下行带宽（Mbps）" "500"
    if valid_mbps "$BW_DOWN"; then break; fi
    warn "请输入 1-1000000 之间的整数"
  done
fi

QUIC_TUNE=0
if confirm "启用 QUIC 窗口调优吗（高延迟/大带宽场景推荐）" y; then
  QUIC_TUNE=1
fi

OBFS=0
if confirm "启用 Salamander 混淆吗（对抗 UDP QoS，客户端需同步填写）" n; then
  OBFS=1
  GEN_OBFS="$(openssl rand -hex 16)"
  prompt OBFS_PASS "混淆密码（直接回车使用随机密码）" "$GEN_OBFS"
  [[ -n "$OBFS_PASS" ]] || die "混淆密码不能为空"
fi

while true; do
  prompt MASQ_URL "伪装站点 URL（真实存在、支持 HTTP/2 的大站）" "https://www.cloudflare.com"
  if [[ "$MASQ_URL" =~ ^https://[^[:space:]]+$ ]]; then break; fi
  warn "请输入以 https:// 开头的 URL"
done

prompt NODE_NAME "节点名称（显示在客户端中）" "hy2-go-go-go"

# SSH 端口探测（配置 UFW 前必须先放行，避免断连）
SSH_PORT="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
if [[ -z "$SSH_PORT" ]]; then
  SSH_PORT="$(awk '/^Port /{print $2; exit}' /etc/ssh/sshd_config 2>/dev/null || true)"
fi
if [[ -z "$SSH_PORT" ]] || ! valid_port "$SSH_PORT"; then
  SSH_PORT=22
fi

USE_UFW=0
info "防火墙将放行：${SSH_PORT}/tcp（SSH）、443/udp（Hysteria 2）、80/tcp（ACME 签发与续期）"
UFW_DEFAULT="y"
if (( CONTAINER )); then
  UFW_DEFAULT="n"
  info "当前为容器环境，建议跳过 UFW，改用服务商面板的防火墙"
fi
if confirm "由脚本配置 UFW 防火墙吗" "$UFW_DEFAULT"; then
  USE_UFW=1
fi

# 汇总确认
step "配置汇总"
cat <<EOF
  域名        ${DOMAIN}
  邮箱        ${EMAIL}
  密码        ${PASSWORD}
  带宽        $(if (( SET_BW )); then printf '上行 %s Mbps / 下行 %s Mbps（Brutal）' "$BW_UP" "$BW_DOWN"; else printf '未设置（类 BBR 模式）'; fi)
  QUIC 调优   $(if (( QUIC_TUNE )); then printf '启用'; else printf '关闭'; fi)
  混淆        $(if (( OBFS )); then printf 'Salamander（密码 %s）' "$OBFS_PASS"; else printf '关闭'; fi)
  伪装站点    ${MASQ_URL}
  节点名称    ${NODE_NAME}
  UFW         $(if (( USE_UFW )); then printf '启用（放行 %s/tcp、443/udp、80/tcp）' "$SSH_PORT"; else printf '跳过，请自行放行 443/udp 与 80/tcp'; fi)
EOF
warn "云厂商安全组/防火墙（阿里云、AWS、Oracle 等）需在控制台另行放行 443/udp 与 80/tcp，UFW 替代不了"
confirm "确认无误，开始部署？" y || die "已取消"

# ---------- 4. 安装 Hysteria 2（官方脚本） ----------

step "4/7 安装 Hysteria 2"
if command -v hysteria >/dev/null; then
  info "检测到已安装的 hysteria（$(hysteria version 2>/dev/null | awk 'NR==1{print $3}' || true)），将升级为最新版"
fi
if (( DRY_RUN )); then
  info "[dry-run] bash <(curl -fsSL https://get.hy2.sh/)"
else
  bash <(curl -fsSL https://get.hy2.sh/) || die "官方安装脚本执行失败"
fi
# 官方脚本的 systemd 单元自带 AmbientCapabilities=CAP_NET_BIND_SERVICE，无需 setcap

# ---------- 5. 写入服务端配置 ----------

step "5/7 写入配置 ${HY2_CONFIG}"

CONFIG="listen: 0.0.0.0:443

acme:
  domains:
    - ${DOMAIN}
  email: ${EMAIL}

auth:
  type: password
  password: $(yaml_quote "$PASSWORD")
"
if (( SET_BW )); then
  CONFIG+="
bandwidth:
  up: ${BW_UP} mbps
  down: ${BW_DOWN} mbps
"
fi
if (( QUIC_TUNE )); then
  CONFIG+="
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
"
fi
if (( OBFS )); then
  CONFIG+="
obfs:
  type: salamander
  salamander:
    password: $(yaml_quote "$OBFS_PASS")
"
fi
CONFIG+="
masquerade:
  type: proxy
  proxy:
    url: $(yaml_quote "$MASQ_URL")
    rewriteHost: true
"

if (( DRY_RUN )); then
  info "[dry-run] 将写入以下配置："
  printf '%s\n' "$CONFIG"
else
  install -d -m 750 "$HY2_DIR"
  if [[ -f "$HY2_CONFIG" ]]; then
    BACKUP="${HY2_CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp -a "$HY2_CONFIG" "$BACKUP"
    info "旧配置已备份到 ${BACKUP}"
  fi
  printf '%s\n' "$CONFIG" >"$HY2_CONFIG"
  chmod 600 "$HY2_CONFIG"
fi
ok "配置已写入"

# ---------- 6. UFW 防火墙 ----------

step "6/7 配置防火墙"
if (( USE_UFW )); then
  if (( DRY_RUN )); then
    info "[dry-run] ufw allow ${SSH_PORT}/tcp; ufw allow 443/udp; ufw allow 80/tcp; yes | ufw enable; ufw status"
  else
    UFW_OK=1
    ufw allow "${SSH_PORT}/tcp" || UFW_OK=0   # 先放行 SSH，避免断连
    ufw allow 443/udp           || UFW_OK=0   # Hysteria 2 本体
    ufw allow 80/tcp            || UFW_OK=0   # ACME HTTP-01 签发+续期（长期保持）
    if (( UFW_OK )); then
      if ! bash -c 'yes | ufw enable'; then
        UFW_OK=0
      fi
    fi
    if (( UFW_OK )); then
      ufw status || true
      ok "UFW 已启用"
    else
      warn "UFW 启用失败：内核无法加载 iptables/nftables 规则（常见于 OpenVZ/LXC 容器）"
      warn "已跳过防火墙配置，不影响 Hysteria 2 运行；请在服务商防火墙面板放行 443/udp 与 80/tcp"
    fi
  fi
else
  warn "已跳过 UFW 配置，请确保系统与云厂商防火墙放行 443/udp 与 80/tcp"
fi

# ---------- 7. 启动并验证 ----------

step "7/7 启动并验证"
run systemctl enable --now "$HY2_SERVICE"

if (( DRY_RUN )); then
  info "[dry-run] 跳过服务状态验证"
else
  sleep 3
  if ! systemctl is-active --quiet "$HY2_SERVICE"; then
    journalctl -u "$HY2_SERVICE" -n 20 --no-pager >&2 || true
    die "服务启动失败，请根据上方日志排查（常见问题：DNS 未指向本机、80/tcp 不可达导致证书签发失败）"
  fi
  if ss -ulnp 2>/dev/null | grep -q ':443 '; then
    ok "服务运行中，UDP/443 正在监听"
  else
    warn "服务已启动但未检测到 UDP/443 监听，请执行 journalctl -u ${HY2_SERVICE} -e 查看日志"
  fi
fi

# ---------- 输出订阅链接 ----------

ENC_PASS="$(urlencode "$PASSWORD")"
ENC_SNI="$(urlencode "$DOMAIN")"
LINK="hy2://${ENC_PASS}@${DOMAIN}:443/?sni=${ENC_SNI}"
if (( OBFS )); then
  LINK+="&obfs=salamander&obfs-password=$(urlencode "$OBFS_PASS")"
fi
LINK+="#$(urlencode "$NODE_NAME")"

if ! (( DRY_RUN )); then
  {
    printf '节点名称：%s\n' "$NODE_NAME"
    printf '服务器：  %s:443（UDP）\n' "$DOMAIN"
    printf '密码：    %s\n' "$PASSWORD"
    printf 'SNI：     %s\n' "$DOMAIN"
    if (( SET_BW )); then printf '带宽：    上行 %s Mbps / 下行 %s Mbps\n' "$BW_UP" "$BW_DOWN"; fi
    if (( OBFS )); then printf '混淆：    salamander / %s\n' "$OBFS_PASS"; fi
    printf '\n订阅链接：\n%s\n' "$LINK"
  } >"$NODE_INFO"
  chmod 600 "$NODE_INFO"
fi

step "部署完成"
printf '%s订阅链接（含密码，请勿公开）：%s\n\n' "$C_G" "$C_0"
printf '  %s\n\n' "$LINK"
if (( DRY_RUN )); then
  warn "dry-run 未对系统做任何修改；去掉 --dry-run 重新执行即可真实部署"
else
  ok "节点信息已保存到 ${NODE_INFO}（权限 600，含明文密码）"
fi
cat <<EOF
使用提示：
  - 将链接导入 v2rayN / NekoBox / sing-box / Streisand 等客户端即可使用
  - 证书由 ACME 签发，客户端无需开启 insecure
  - 若设置了带宽，客户端中也填相同上下行，否则 Brutal 不生效
  - 这是单节点链接，不是订阅；多节点订阅需另搭订阅转换器

维护命令：
  systemctl status ${HY2_SERVICE}     # 查看状态
  journalctl -u ${HY2_SERVICE} -f     # 实时日志
  systemctl restart ${HY2_SERVICE}    # 改配置后重启
  bash <(curl -fsSL https://get.hy2.sh/) --remove   # 卸载核心
EOF
