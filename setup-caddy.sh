#!/usr/bin/env bash
# =============================================================================
# Caddy Script v1.0 By Merlin
# Caddy 反向代理一键配置 (Debian 12/13)
# 调用:    ca
# 安装:    wget -O ca https://raw.githubusercontent.com/merlin-node/caddy/main/setup-caddy.sh && chmod +x ca && sudo mv ca /usr/local/bin/ca
# =============================================================================

set -o pipefail

SCRIPT_VERSION="1.0"
SCRIPT_AUTHOR="Merlin"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/merlin-node/caddy/main/setup-caddy.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

CADDYFILE="/etc/caddy/Caddyfile"
META_DIR="/etc/caddy/.meta"
META_FILE="${META_DIR}/current"
CADDY_LOG_DIR="/var/log/caddy"
CA_SCRIPT_PATH="/usr/local/bin/ca"

# =============================================================================
# 输出工具
# =============================================================================
msg()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }
ok()   { echo -e "${GREEN}[成功]${NC} $*"; }

term_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 60)
    (( w < 40 )) && w=40
    (( w > 80 )) && w=80
    echo "$w"
}

hr() {
    local w; w=$(term_width)
    printf "${BLUE}%${w}s${NC}\n" '' | tr ' ' '='
}

sec() {
    local title="$1" w side_eq
    w=$(term_width)
    local bytes chars non_ascii_chars ascii_chars visual
    bytes=$(printf '%s' " ${title} " | wc -c)
    chars=$(printf '%s' " ${title} " | wc -m)
    non_ascii_chars=$(( (bytes - chars) / 2 ))
    ascii_chars=$(( chars - non_ascii_chars ))
    visual=$(( ascii_chars + non_ascii_chars * 2 ))
    side_eq=$(( (w - visual) / 2 ))
    (( side_eq < 3 )) && side_eq=3
    local left right
    left=$(printf "%${side_eq}s" '' | tr ' ' '=')
    right=$(printf "%${side_eq}s" '' | tr ' ' '=')
    echo -e "${BLUE}${left} ${BOLD}${title}${NC}${BLUE} ${right}${NC}"
}

pause() {
    echo
    read -rp "$(echo -e "${CYAN}按回车键继续...${NC}")" _ || true
}

# =============================================================================
# 前置检查
# =============================================================================
need_root() {
    [[ $EUID -eq 0 ]] || { err "请用 root 运行"; exit 1; }
}

check_debian() {
    [[ -f /etc/os-release ]] || { err "无法识别系统"; exit 1; }
    . /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        warn "本脚本仅在 Debian/Ubuntu 测试过，当前: $ID $VERSION_ID"
        read -rp "仍要继续? [y/N]: " a
        [[ "$a" =~ ^[Yy]$ ]] || exit 0
    fi
}

# =============================================================================
# Caddy 安装管理
# =============================================================================
install_caddy() {
    if command -v caddy >/dev/null 2>&1; then
        return 0
    fi
    msg "安装依赖..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null 2>&1

    msg "添加 Caddy 官方源..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null

    msg "安装 Caddy..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y caddy >/dev/null 2>&1

    mkdir -p "$CADDY_LOG_DIR" "$META_DIR"
    ok "Caddy 安装完成"
}

caddy_version() {
    caddy version 2>/dev/null | awk '{print $1}' | head -1
}

# =============================================================================
# 工具函数
# =============================================================================

# 检查本机后端端口是否有服务监听
# 本机后端必须有进程在监听，否则反代过去 502
check_backend_port() {
    local ip="$1" port="$2"
    case "$ip" in
        127.0.0.1|localhost|::1) ;;
        *) return 0 ;;   # 远程后端不检查本机
    esac

    local listener
    listener=$(ss -tlnp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {print; exit}')

    if [[ -z "$listener" ]]; then
        warn "本机端口 ${port} 当前无服务监听"
        echo -e "  ${YELLOW}Caddy 反代过去会返回错误，请先启动后端服务${NC}"
        echo
        read -rp "$(echo -e "${CYAN}仍要继续? [y/N]: ${NC}")" go
        [[ "$go" =~ ^[Yy]$ ]] || return 1
    else
        local proc
        proc=$(echo "$listener" | grep -oP '"\K[^"]+' | head -1)
        echo -e "  ${GREEN}[√]${NC} 后端服务已监听：${proc:-unknown} on :${port}"
    fi
    return 0
}

write_and_apply() {
    local svc="$1" domain="$2" ip="$3" port="$4" timeout="$5"

    mkdir -p "$(dirname "$CADDYFILE")" "$META_DIR" "$CADDY_LOG_DIR"

    cat > "$CADDYFILE" << EOF
# 由 ca 工具生成，元数据存于 ${META_FILE}
${domain} {
    log {
        output file ${CADDY_LOG_DIR}/${svc}.log {
            roll_size 10mb
            roll_keep 5
        }
    }

    reverse_proxy ${ip}:${port} {
        transport http {
            read_timeout ${timeout}s
            write_timeout ${timeout}s
        }

        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

    cat > "$META_FILE" << EOF
SVC_NAME=${svc}
DOMAIN=${domain}
BACKEND_IP=${ip}
BACKEND_PORT=${port}
TIMEOUT=${timeout}
EOF

    echo
    msg "校验配置..."
    if ! caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
        err "配置校验失败"
        caddy validate --config "$CADDYFILE" --adapter caddyfile 2>&1 | sed 's/^/  /'
        return 1
    fi
    ok "校验通过"

    msg "应用配置..."
    systemctl enable caddy >/dev/null 2>&1 || true
    if systemctl is-active --quiet caddy; then
        systemctl reload caddy
        ok "Caddy 已重载"
    else
        systemctl start caddy
        ok "Caddy 已启动"
    fi
}

load_meta() {
    [[ -f "$META_FILE" ]] || return 1
    # shellcheck disable=SC1090
    source "$META_FILE"
    return 0
}

# =============================================================================
# 菜单：生成 / 查看 / 更改 配置
# =============================================================================
menu_add() {
    clear; show_banner
    sec "生成 Caddyfile"

    if [[ -f "$CADDYFILE" ]] && load_meta; then
        echo -e "  ${YELLOW}已存在配置${NC}"
        echo
        echo "  服务:     ${SVC_NAME}"
        echo "  域名:     ${DOMAIN}"
        echo "  后端:     ${BACKEND_IP}:${BACKEND_PORT}"
        echo
        echo -e "  ${YELLOW}继续将覆盖现有配置${NC}"
        hr
        read -rp "$(echo -e "${CYAN}是否继续? [y/N]: ${NC}")" go
        [[ "$go" =~ ^[Yy]$ ]] || return
        echo
    fi

    local svc domain ip port timeout
    read -rp "$(echo -e "${CYAN}服务名称（用于日志文件名，例如 myapp）: ${NC}")" svc
    [[ -z "$svc" ]] && { err "服务名称不能为空"; pause; return; }

    read -rp "$(echo -e "${CYAN}域名（例如 api.example.com）: ${NC}")" domain
    [[ -z "$domain" ]] && { err "域名不能为空"; pause; return; }

    read -rp "$(echo -e "${CYAN}后端 IP [${NC}127.0.0.1${CYAN}]: ${NC}")" ip
    ip="${ip:-127.0.0.1}"

    read -rp "$(echo -e "${CYAN}后端端口: ${NC}")" port
    [[ -z "$port" ]] && { err "端口不能为空"; pause; return; }
    echo
    if ! check_backend_port "$ip" "$port"; then
        pause; return
    fi
    echo

    read -rp "$(echo -e "${CYAN}超时(秒) [${NC}300${CYAN}]: ${NC}")" timeout
    timeout="${timeout:-300}"

    if write_and_apply "$svc" "$domain" "$ip" "$port" "$timeout"; then
        echo
        hr
        echo -e "  ${GREEN}[√]${NC} 部署完成"
        echo
        echo "  域名:     https://${domain}"
        echo "  后端:     ${ip}:${port}"
        echo "  超时:     ${timeout}s"
        echo "  日志:     ${CADDY_LOG_DIR}/${svc}.log"
        hr
    fi
    pause
}

menu_view() {
    clear; show_banner
    sec "查看配置"

    if ! load_meta; then
        warn "尚未生成配置"
        echo -e "  ${YELLOW}请先用主菜单的「添加配置」创建${NC}"
        pause; return
    fi

    echo "  服务名称: ${SVC_NAME}"
    echo "  域名:     ${DOMAIN}"
    echo "  后端 IP:  ${BACKEND_IP}"
    echo "  后端端口: ${BACKEND_PORT}"
    echo "  超时:     ${TIMEOUT}s"
    echo "  日志:     ${CADDY_LOG_DIR}/${SVC_NAME}.log"
    echo
    if systemctl is-active --quiet caddy; then
        echo -e "  状态:     ${GREEN}running${NC}"
    else
        echo -e "  状态:     ${RED}stopped${NC}"
    fi
    hr
    echo -e "  ${BLUE}>>> ${BOLD}${CADDYFILE}${NC}"
    echo
    if [[ -f "$CADDYFILE" ]]; then
        sed 's/^/  /' "$CADDYFILE"
    else
        err "文件不存在"
    fi
    pause
}

menu_edit() {
    while :; do
        clear; show_banner
        sec "更改配置"

        if ! load_meta; then
            warn "尚未生成配置"
            echo -e "  ${YELLOW}请先用主菜单的「添加配置」创建${NC}"
            pause; return
        fi

        echo "  1) 服务名称   ${SVC_NAME}"
        echo "  2) 域名       ${DOMAIN}"
        echo "  3) 后端 IP    ${BACKEND_IP}"
        echo "  4) 后端端口   ${BACKEND_PORT}"
        echo "  5) 超时       ${TIMEOUT}s"
        echo "  0) 返回上一页"
        hr
        local c new
        read -rp "$(echo -e "${CYAN}选择要修改的项 [0-5]: ${NC}")" c
        case "$c" in
            0|"") return ;;
            1)
                read -rp "$(echo -e "${CYAN}服务名称 [${NC}${SVC_NAME}${CYAN}]: ${NC}")" new
                SVC_NAME="${new:-$SVC_NAME}"
                ;;
            2)
                read -rp "$(echo -e "${CYAN}域名 [${NC}${DOMAIN}${CYAN}]: ${NC}")" new
                DOMAIN="${new:-$DOMAIN}"
                ;;
            3)
                read -rp "$(echo -e "${CYAN}后端 IP [${NC}${BACKEND_IP}${CYAN}]: ${NC}")" new
                BACKEND_IP="${new:-$BACKEND_IP}"
                ;;
            4)
                read -rp "$(echo -e "${CYAN}后端端口 [${NC}${BACKEND_PORT}${CYAN}]: ${NC}")" new
                new="${new:-$BACKEND_PORT}"
                if [[ "$new" != "$BACKEND_PORT" ]]; then
                    echo
                    if ! check_backend_port "$BACKEND_IP" "$new"; then
                        pause; continue
                    fi
                fi
                BACKEND_PORT="$new"
                ;;
            5)
                read -rp "$(echo -e "${CYAN}超时(秒) [${NC}${TIMEOUT}${CYAN}]: ${NC}")" new
                TIMEOUT="${new:-$TIMEOUT}"
                ;;
            *) err "无效"; sleep 1; continue ;;
        esac

        write_and_apply "$SVC_NAME" "$DOMAIN" "$BACKEND_IP" "$BACKEND_PORT" "$TIMEOUT"
        pause
    done
}

# =============================================================================
# 菜单：Caddy 服务管理
# =============================================================================
view_log() {
    local n="${1:-50}"
    if ! load_meta; then
        err "尚未生成配置，无可查看日志"
        return
    fi
    local f="${CADDY_LOG_DIR}/${SVC_NAME}.log"
    if [[ -s "$f" ]]; then
        echo -e "  ${BLUE}>>> ${BOLD}${f}${NC}  (最近 ${n} 行)"
        echo
        tail -n "$n" "$f" | sed 's/^/  /'
    else
        warn "Caddy 文件日志为空，改读 systemd 日志"
        echo
        journalctl -u caddy -n "$n" --no-pager | sed 's/^/  /'
    fi
}

menu_caddy() {
    while :; do
        clear; show_banner
        sec "Caddy 服务管理"
        local active="${RED}stopped${NC}" enabled="${RED}未启用${NC}"
        local ver
        systemctl is-active --quiet caddy && active="${GREEN}running${NC}"
        systemctl is-enabled --quiet caddy 2>/dev/null && enabled="${GREEN}开机自启${NC}"
        ver=$(caddy_version)
        echo -e "  状态: ${active}    自启: ${enabled}    版本: ${ver:-未知}"
        hr
        echo "  1) 启动 Caddy"
        echo "  2) 停止 Caddy"
        echo "  3) 重启 Caddy"
        echo "  4) 查看 systemd 状态"
        echo "  5) 最近 50 行日志"
        echo "  6) 实时跟踪日志 (Ctrl+C 退出)"
        echo "  7) 清空日志文件"
        echo "  8) 更新 Caddy 到最新版"
        echo "  0) 返回上一页"
        hr
        local c
        read -rp "$(echo -e "${CYAN}请选择 [0-8]: ${NC}")" c
        case "$c" in
            1) systemctl start caddy && ok "已启动"; sleep 1 ;;
            2) systemctl stop caddy && ok "已停止"; sleep 1 ;;
            3) systemctl restart caddy && ok "已重启"; sleep 1 ;;
            4) clear; systemctl status caddy --no-pager -l | head -n 30; pause ;;
            5) clear; view_log 50; pause ;;
            6) clear; echo "Ctrl+C 退出"
               if load_meta && [[ -s "${CADDY_LOG_DIR}/${SVC_NAME}.log" ]]; then
                   tail -f "${CADDY_LOG_DIR}/${SVC_NAME}.log"
               else
                   journalctl -u caddy -f
               fi ;;
            7)
                if load_meta; then
                    : > "${CADDY_LOG_DIR}/${SVC_NAME}.log"
                    ok "日志已清空"
                else
                    err "无配置可清"
                fi
                sleep 1
                ;;
            8) apt-get update -y >/dev/null 2>&1
               apt-get install --only-upgrade -y caddy
               ok "Caddy 已更新至 $(caddy_version)"
               pause ;;
            0|"") return ;;
            *) err "无效"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# 菜单：脚本管理
# =============================================================================
menu_script() {
    while :; do
        clear; show_banner
        sec "脚本管理"
        echo "  当前版本: v${SCRIPT_VERSION}  作者: ${SCRIPT_AUTHOR}"
        echo "  脚本路径: ${CA_SCRIPT_PATH}"
        echo "  更新源:   ${SCRIPT_UPDATE_URL}"
        hr
        echo "  1) 更新脚本"
        echo "  2) 一键卸载 (清除所有内容)"
        echo "  0) 返回上一页"
        hr
        local c
        read -rp "$(echo -e "${CYAN}请选择 [0-2]: ${NC}")" c
        case "$c" in
            1) update_script; pause ;;
            2) do_uninstall ;;
            0|"") return ;;
            *) err "无效"; sleep 1 ;;
        esac
    done
}

update_script() {
    msg "从 ${SCRIPT_UPDATE_URL} 下载新版..."
    local tmp; tmp=$(mktemp)
    if curl -fsSL "$SCRIPT_UPDATE_URL" -o "$tmp"; then
        if head -n 1 "$tmp" | grep -q '^#!/.*bash'; then
            install -m 755 "$tmp" "$CA_SCRIPT_PATH"
            rm -f "$tmp"
            ok "脚本已更新，请重新执行 ca"
            exit 0
        else
            err "下载内容不是有效脚本"
            rm -f "$tmp"
        fi
    else
        err "下载失败，请检查 SCRIPT_UPDATE_URL"
        rm -f "$tmp"
    fi
}

do_uninstall() {
    clear; show_banner
    sec "${RED}一键卸载${NC}"
    echo "  将删除: Caddy、配置、systemd 服务、日志、ca 命令"
    echo
    read -rp "$(echo -e "${YELLOW}确定卸载? 输入 ${BOLD}YES${NC}${YELLOW} 确认: ${NC}")" y
    [[ "$y" == "YES" ]] || { warn "已取消"; pause; return; }
    systemctl stop caddy 2>/dev/null
    systemctl disable caddy 2>/dev/null
    apt-get purge -y caddy >/dev/null 2>&1
    rm -rf /etc/caddy "$CADDY_LOG_DIR" /var/lib/caddy
    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f "$CA_SCRIPT_PATH"
    ok "卸载完成，再见"
    exit 0
}

# =============================================================================
# Banner & 主菜单
# =============================================================================
show_banner() {
    local ver active domain
    ver=$(caddy_version)
    if systemctl is-active --quiet caddy; then
        active="${GREEN}running${NC}"
    else
        active="${RED}stopped${NC}"
    fi
    if load_meta; then
        domain="$DOMAIN"
    else
        domain="${YELLOW}未配置${NC}"
    fi
    local title="Caddy Script v${SCRIPT_VERSION} By ${SCRIPT_AUTHOR}"
    local w side_eq bytes chars non_ascii_chars ascii_chars visual
    w=$(term_width)
    bytes=$(printf '%s' " ${title} " | wc -c)
    chars=$(printf '%s' " ${title} " | wc -m)
    non_ascii_chars=$(( (bytes - chars) / 2 ))
    ascii_chars=$(( chars - non_ascii_chars ))
    visual=$(( ascii_chars + non_ascii_chars * 2 ))
    side_eq=$(( (w - visual) / 2 ))
    (( side_eq < 3 )) && side_eq=3
    local left right
    left=$(printf "%${side_eq}s" '' | tr ' ' '=')
    right=$(printf "%${side_eq}s" '' | tr ' ' '=')
    echo -e "${GREEN}${left} ${BOLD}${title}${NC}${GREEN} ${right}${NC}"
    echo
    echo -e "  caddy:    ${ver:-未安装}"
    echo
    echo -e "  状态:     ${active}    域名: ${domain}"
    echo
    hr
}

main_menu() {
    while :; do
        clear; show_banner
        echo
        echo "  1. 添加配置"
        echo
        echo "  2. 更改配置"
        echo
        echo "  3. 查看配置"
        echo
        echo "  4. Caddy 服务管理"
        echo
        echo "  5. 脚本管理"
        echo
        echo "  0. 退出"
        echo
        hr
        local c
        read -rp "$(echo -e "${CYAN}请输入选项 [0-5]: ${NC}")" c
        case "$c" in
            1) menu_add ;;
            2) menu_edit ;;
            3) menu_view ;;
            4) menu_caddy ;;
            5) menu_script ;;
            0|"") clear; exit 0 ;;
            *) err "无效"; sleep 1 ;;
        esac
    done
}

first_install() {
    clear
    local title="Caddy Script v${SCRIPT_VERSION} By ${SCRIPT_AUTHOR}"
    local w side_eq bytes chars non_ascii_chars ascii_chars visual
    w=$(term_width)
    bytes=$(printf '%s' " ${title} " | wc -c)
    chars=$(printf '%s' " ${title} " | wc -m)
    non_ascii_chars=$(( (bytes - chars) / 2 ))
    ascii_chars=$(( chars - non_ascii_chars ))
    visual=$(( ascii_chars + non_ascii_chars * 2 ))
    side_eq=$(( (w - visual) / 2 ))
    (( side_eq < 3 )) && side_eq=3
    local left right
    left=$(printf "%${side_eq}s" '' | tr ' ' '=')
    right=$(printf "%${side_eq}s" '' | tr ' ' '=')
    echo -e "${GREEN}${left} ${BOLD}${title}${NC}${GREEN} ${right}${NC}"
    echo
    sec "首次运行：开始安装"
    check_debian
    install_caddy
    hr
    ok "安装完成。以后输入 ${BOLD}ca${NC} 即可呼出菜单。"
    hr
    pause
}

main() {
    need_root
    if ! command -v caddy >/dev/null 2>&1; then
        first_install
    fi
    main_menu
}

main "$@"
