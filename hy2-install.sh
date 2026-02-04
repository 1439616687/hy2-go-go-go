#!/bin/bash

#===============================================================================
# Hysteria 2 一键安装脚本
# 适用于 Debian/Ubuntu 系统
# 项目地址: https://github.com/1439616687/hy2-go-go-go
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 颜色定义
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# 输出函数
#-------------------------------------------------------------------------------
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║             Hysteria 2 一键安装脚本                           ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${CYAN}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_config() {
    echo -e "  ${PURPLE}•${NC} $1: ${WHITE}$2${NC}"
}

#-------------------------------------------------------------------------------
# 检查函数
#-------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo bash $0"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi

    case $OS in
        ubuntu|debian)
            print_success "检测到系统: $PRETTY_NAME"
            ;;
        *)
            print_warning "此脚本针对 Debian/Ubuntu 优化，当前系统: $OS"
            read -p "是否继续？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                exit 0
            fi
            ;;
    esac
}

check_existing_installation() {
    if systemctl is-active --quiet hysteria-server 2>/dev/null; then
        print_warning "检测到 Hysteria 2 已在运行"
        echo ""
        echo -e "  ${YELLOW}1)${NC} 重新安装（会覆盖现有配置）"
        echo -e "  ${YELLOW}2)${NC} 仅更新 Hysteria 2"
        echo -e "  ${YELLOW}3)${NC} 查看当前配置"
        echo -e "  ${YELLOW}4)${NC} 卸载 Hysteria 2"
        echo -e "  ${YELLOW}0)${NC} 退出"
        echo ""
        read -p "请选择 [0-4]: " choice
        
        case $choice in
            1)
                print_info "将进行重新安装..."
                systemctl stop hysteria-server 2>/dev/null || true
                ;;
            2)
                update_hysteria
                exit 0
                ;;
            3)
                show_current_config
                exit 0
                ;;
            4)
                uninstall_hysteria
                exit 0
                ;;
            *)
                print_info "退出安装"
                exit 0
                ;;
        esac
    fi
}

#-------------------------------------------------------------------------------
# 功能函数
#-------------------------------------------------------------------------------
get_hysteria_version() {
    # 从 "Version:    v2.7.0" 格式中提取版本号
    hysteria version 2>&1 | grep "Version:" | awk '{print $2}'
}

update_hysteria() {
    print_step "更新 Hysteria 2"
    bash <(curl -fsSL https://get.hy2.sh/)
    systemctl restart hysteria-server
    print_success "更新完成"
    local version=$(get_hysteria_version)
    [[ -n "$version" ]] && print_info "当前版本: $version"
}

show_current_config() {
    print_step "当前配置"
    if [[ -f /etc/hysteria/config.yaml ]]; then
        cat /etc/hysteria/config.yaml
        echo ""
        print_step "生成客户端链接"
        generate_client_link_from_config
    else
        print_error "配置文件不存在"
    fi
}

generate_client_link_from_config() {
    if [[ -f /etc/hysteria/config.yaml ]]; then
        local domain=$(grep -A1 "domains:" /etc/hysteria/config.yaml | tail -1 | sed 's/.*- //' | tr -d ' ')
        local password=$(grep "password:" /etc/hysteria/config.yaml | head -1 | awk '{print $2}')
        local port=$(grep "listen:" /etc/hysteria/config.yaml | sed 's/.*://' | tr -d ' ')
        
        if [[ -n "$domain" && -n "$password" && -n "$port" ]]; then
            local encoded_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$password', safe=''))")
            echo ""
            echo -e "${GREEN}客户端连接链接:${NC}"
            echo ""
            echo -e "${WHITE}hysteria2://${encoded_password}@${domain}:${port}/?sni=${domain}&insecure=0${NC}"
            echo ""
        fi
    fi
}

uninstall_hysteria() {
    print_step "卸载 Hysteria 2"
    read -p "确定要卸载吗？配置文件将被保留。(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        systemctl stop hysteria-server 2>/dev/null || true
        systemctl disable hysteria-server 2>/dev/null || true
        bash <(curl -fsSL https://get.hy2.sh/) --remove
        print_success "Hysteria 2 已卸载"
        print_info "配置文件保留在 /etc/hysteria/"
    fi
}

get_server_ip() {
    # 尝试多种方式获取公网 IP
    SERVER_IP=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null) ||
    SERVER_IP=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null) ||
    SERVER_IP=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null) ||
    SERVER_IP=""
    
    if [[ -z "$SERVER_IP" ]]; then
        print_warning "无法自动获取服务器公网 IP"
        read -p "请手动输入服务器公网 IP: " SERVER_IP
    fi
}

collect_user_input() {
    print_step "配置信息收集"
    
    # 获取服务器 IP
    print_info "正在获取服务器公网 IP..."
    get_server_ip
    print_success "服务器 IP: $SERVER_IP"
    echo ""
    
    # 域名
    while true; do
        read -p "请输入已解析到本服务器的域名: " DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            print_error "域名不能为空"
            continue
        fi
        
        print_info "正在验证域名解析..."
        RESOLVED_IP=$(dig +short A "$DOMAIN" @1.1.1.1 2>/dev/null | head -1)
        
        if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
            print_success "域名解析验证通过: $DOMAIN -> $RESOLVED_IP"
            break
        else
            print_warning "域名解析结果 ($RESOLVED_IP) 与服务器 IP ($SERVER_IP) 不匹配"
            echo ""
            echo -e "  ${YELLOW}1)${NC} 重新输入域名"
            echo -e "  ${YELLOW}2)${NC} 忽略警告继续（可能导致证书申请失败）"
            echo -e "  ${YELLOW}0)${NC} 退出"
            echo ""
            read -p "请选择 [0-2]: " dns_choice
            case $dns_choice in
                1) continue ;;
                2) 
                    print_warning "继续安装，但请确保域名解析正确"
                    break
                    ;;
                *) exit 0 ;;
            esac
        fi
    done
    echo ""
    
    # 邮箱
    while true; do
        read -p "请输入邮箱 (用于 ACME 证书): " EMAIL
        if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "邮箱格式不正确"
        fi
    done
    echo ""
    
    # 密码
    echo "认证密码设置:"
    echo -e "  ${YELLOW}1)${NC} 自动生成随机密码（推荐）"
    echo -e "  ${YELLOW}2)${NC} 手动输入密码"
    echo ""
    read -p "请选择 [1-2] (默认 1): " pwd_choice
    
    case $pwd_choice in
        2)
            while true; do
                read -s -p "请输入密码: " PASSWORD
                echo ""
                read -s -p "请再次输入密码: " PASSWORD2
                echo ""
                if [[ "$PASSWORD" == "$PASSWORD2" && -n "$PASSWORD" ]]; then
                    break
                else
                    print_error "密码不匹配或为空"
                fi
            done
            ;;
        *)
            PASSWORD=$(openssl rand -base64 32)
            print_success "已生成随机密码"
            ;;
    esac
    echo ""
    
    # 端口
    read -p "请输入监听端口 (默认 443): " PORT
    PORT=${PORT:-443}
    echo ""
    
    # 伪装网站
    echo "伪装网站设置:"
    echo -e "  ${YELLOW}1)${NC} 使用默认 (bing.com)"
    echo -e "  ${YELLOW}2)${NC} 自定义伪装网站"
    echo ""
    read -p "请选择 [1-2] (默认 1): " mask_choice
    
    case $mask_choice in
        2)
            read -p "请输入伪装网站 URL (如 https://www.example.com): " MASQUERADE_URL
            ;;
        *)
            MASQUERADE_URL="https://www.bing.com"
            ;;
    esac
    
    # 确认配置
    echo ""
    print_step "配置确认"
    print_config "域名" "$DOMAIN"
    print_config "邮箱" "$EMAIL"
    print_config "端口" "$PORT"
    print_config "伪装网站" "$MASQUERADE_URL"
    print_config "服务器 IP" "$SERVER_IP"
    echo ""
    
    read -p "确认以上配置？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_info "重新开始配置收集..."
        collect_user_input
    fi
}

install_basic_dependencies() {
    # 静默安装 dig 命令所需的 dnsutils
    if ! command -v dig &> /dev/null; then
        print_info "安装基础组件..."
        apt update -qq > /dev/null 2>&1
        apt install -y -qq dnsutils > /dev/null 2>&1
    fi
}

install_dependencies() {
    print_step "安装依赖"
    
    print_info "更新软件包列表..."
    apt update -qq
    
    print_info "安装必要组件..."
    apt install -y -qq curl nano ufw dnsutils openssl python3 > /dev/null 2>&1
    
    print_success "依赖安装完成"
}

configure_system() {
    print_step "系统优化"
    
    # 检查 BBR 是否已启用
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    
    if [[ "$current_cc" == "bbr" ]]; then
        print_success "BBR 已启用"
    else
        print_info "正在启用 BBR..."
        
        # 检查内核是否支持 BBR
        if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            cat >> /etc/sysctl.conf << EOF

# BBR 拥塞控制 (Hysteria 2 安装脚本添加)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
            sysctl -p > /dev/null 2>&1
            print_success "BBR 已启用"
        else
            print_warning "当前内核不支持 BBR，跳过"
        fi
    fi
}

configure_firewall() {
    print_step "配置防火墙"
    
    # 检查 UFW 状态
    if ! command -v ufw &> /dev/null; then
        print_info "安装 UFW..."
        apt install -y -qq ufw > /dev/null 2>&1
    fi
    
    print_info "配置防火墙规则..."
    
    # 确保 SSH 端口开放
    ufw allow 22/tcp > /dev/null 2>&1
    
    # Hysteria 2 端口
    ufw allow ${PORT}/udp > /dev/null 2>&1
    ufw allow ${PORT}/tcp > /dev/null 2>&1
    
    # ACME HTTP-01 验证
    ufw allow 80/tcp > /dev/null 2>&1
    
    # 启用 UFW
    echo "y" | ufw enable > /dev/null 2>&1
    
    print_success "防火墙配置完成"
    print_info "已开放端口: 22/tcp, 80/tcp, ${PORT}/tcp, ${PORT}/udp"
}

install_hysteria() {
    print_step "安装 Hysteria 2"
    
    print_info "下载并安装 Hysteria 2..."
    bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1
    
    if command -v hysteria &> /dev/null; then
        print_success "Hysteria 2 安装完成"
        # 从 "Version:    v2.7.0" 格式中提取版本号
        local version=$(get_hysteria_version)
        if [[ -n "$version" ]]; then
            print_info "版本: $version"
        fi
    else
        print_error "Hysteria 2 安装失败"
        exit 1
    fi
}

configure_hysteria() {
    print_step "配置 Hysteria 2"
    
    # 备份已有配置
    if [[ -f /etc/hysteria/config.yaml ]]; then
        cp /etc/hysteria/config.yaml /etc/hysteria/config.yaml.bak.$(date +%Y%m%d%H%M%S)
        print_info "已备份原配置文件"
    fi
    
    # 创建配置目录
    mkdir -p /etc/hysteria
    
    # 写入配置
    cat > /etc/hysteria/config.yaml << EOF
# Hysteria 2 服务端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

listen: 0.0.0.0:${PORT}

acme:
  domains:
    - ${DOMAIN}
  email: ${EMAIL}

auth:
  type: password
  password: ${PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: ${MASQUERADE_URL}
    rewriteHost: true
EOF
    
    print_success "配置文件已生成"
    
    # 设置权限
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/hysteria 2>/dev/null || true
}

start_service() {
    print_step "启动服务"
    
    print_info "启动 Hysteria 2 服务..."
    systemctl enable hysteria-server > /dev/null 2>&1
    systemctl start hysteria-server
    
    # 等待服务启动和证书申请
    print_info "等待服务启动和证书申请 (最多 30 秒)..."
    
    local max_wait=30
    local wait_time=0
    local success=false
    
    while [[ $wait_time -lt $max_wait ]]; do
        sleep 2
        wait_time=$((wait_time + 2))
        
        if systemctl is-active --quiet hysteria-server; then
            # 检查日志是否有成功标志
            if journalctl -u hysteria-server --no-pager -n 20 2>/dev/null | grep -qiE "server up and running|listening"; then
                success=true
                break
            fi
        fi
        
        echo -ne "\r${CYAN}[信息]${NC} 已等待 ${wait_time} 秒..."
    done
    echo ""
    
    if $success; then
        print_success "服务启动成功"
    else
        # 检查服务状态
        if systemctl is-active --quiet hysteria-server; then
            print_success "服务已启动"
        else
            print_error "服务启动失败"
            print_info "查看错误日志:"
            echo ""
            journalctl -u hysteria-server --no-pager -n 20
            echo ""
            print_info "常见问题:"
            echo "  1. 域名解析不正确"
            echo "  2. 80 端口被占用（ACME 验证需要）"
            echo "  3. 防火墙未正确配置"
            echo ""
            print_info "可尝试手动重启: systemctl restart hysteria-server"
            exit 1
        fi
    fi
}

show_result() {
    print_step "安装完成"
    
    # 生成 URL 编码的密码
    ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PASSWORD', safe=''))")
    
    # 生成客户端链接
    CLIENT_LINK="hysteria2://${ENCODED_PASSWORD}@${DOMAIN}:${PORT}/?sni=${DOMAIN}&insecure=0"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    安装成功完成                               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}服务器信息:${NC}"
    print_config "域名" "$DOMAIN"
    print_config "端口" "$PORT"
    print_config "密码" "$PASSWORD"
    echo ""
    
    echo -e "${WHITE}客户端连接链接:${NC}"
    echo ""
    echo -e "${YELLOW}${CLIENT_LINK}${NC}"
    echo ""
    
    echo -e "${WHITE}常用命令:${NC}"
    echo -e "  ${PURPLE}•${NC} 查看状态: ${CYAN}systemctl status hysteria-server${NC}"
    echo -e "  ${PURPLE}•${NC} 查看日志: ${CYAN}journalctl -u hysteria-server -f${NC}"
    echo -e "  ${PURPLE}•${NC} 重启服务: ${CYAN}systemctl restart hysteria-server${NC}"
    echo -e "  ${PURPLE}•${NC} 编辑配置: ${CYAN}nano /etc/hysteria/config.yaml${NC}"
    echo ""
    
    # 保存信息到文件
    cat > /root/hysteria2-info.txt << EOF
Hysteria 2 安装信息
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
================================================

服务器信息:
  域名: ${DOMAIN}
  端口: ${PORT}
  密码: ${PASSWORD}

客户端连接链接:
${CLIENT_LINK}

配置文件位置: /etc/hysteria/config.yaml

常用命令:
  查看状态: systemctl status hysteria-server
  查看日志: journalctl -u hysteria-server -f
  重启服务: systemctl restart hysteria-server
  停止服务: systemctl stop hysteria-server
  编辑配置: nano /etc/hysteria/config.yaml
  
更新 Hysteria 2:
  bash <(curl -fsSL https://get.hy2.sh/)
  systemctl restart hysteria-server
EOF
    
    print_success "安装信息已保存到: /root/hysteria2-info.txt"
    echo ""
}

#-------------------------------------------------------------------------------
# 主流程
#-------------------------------------------------------------------------------
main() {
    print_banner
    
    # 检查
    check_root
    check_os
    check_existing_installation
    
    # 先安装基础依赖（dig 命令需要 dnsutils）
    install_basic_dependencies
    
    # 收集配置
    collect_user_input
    
    # 安装流程
    install_dependencies
    configure_system
    configure_firewall
    install_hysteria
    configure_hysteria
    start_service
    
    # 显示结果
    show_result
}

# 运行主流程
main "$@"
