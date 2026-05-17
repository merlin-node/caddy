#!/bin/bash
# Caddy 反向代理配置工具 (Debian/Ubuntu)
#===================================
# 一键安装:
#   wget -O ca https://raw.githubusercontent.com/merlin-node/caddy/main/setup-caddy.sh && chmod +x ca && sudo mv ca /usr/local/bin/ca
# 之后在 VPS 里直接输入 ca 即可运行
#===================================

set -e

CADDYFILE="/etc/caddy/Caddyfile"
META_DIR="/etc/caddy/.meta"

# ---------- 工具函数 ----------

pause() {
    echo ""
    read -p "按回车返回主菜单..."
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "[错误] 请用 sudo 或 root 运行: sudo ca"
        exit 1
    fi
}

# 自动检测并安装 Caddy
ensure_caddy_installed() {
    if command -v caddy >/dev/null 2>&1; then
        return
    fi

    clear
    echo "========================================"
    echo "  检测到 Caddy 未安装"
    echo "========================================"
    echo ""
    echo "本工具需要 Caddy 才能工作。"
    echo "将通过官方源安装 Caddy（来自 cloudsmith.io/~caddy）。"
    echo ""
    read -p "是否现在安装？[Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "已取消，无法继续。"
        exit 1
    fi

    echo ""
    echo "→ 安装依赖..."
    apt update
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

    echo "→ 添加 Caddy 官方源..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list

    echo "→ 安装 Caddy..."
    apt update
    apt install -y caddy

    mkdir -p /var/log/caddy "$META_DIR"

    echo ""
    echo "Caddy 安装完成。"
    pause
}

# 端口占用检测（仅本机后端时才有意义）
check_port_in_use() {
    local ip="$1"
    local port="$2"
    # 远程后端不检查本机端口
    if [ "$ip" != "127.0.0.1" ] && [ "$ip" != "localhost" ] && [ "$ip" != "::1" ]; then
        return 0
    fi
    if ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
        echo ""
        echo "[警告] 本机端口 ${port} 已被占用:"
        ss -tlnp | grep -E "[:.]${port}\b" || true
        echo ""
        read -p "仍要继续吗？[y/N]: " GO
        if [[ ! "$GO" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

# 写入 Caddyfile + 元数据，校验，reload
write_and_apply() {
    local svc="$1" domain="$2" ip="$3" port="$4" timeout="$5"

    mkdir -p "$(dirname "$CADDYFILE")" "$META_DIR" /var/log/caddy

    cat > "$CADDYFILE" << EOF
# 由 ca 工具生成，请勿手动修改注释
${domain} {
    log {
        output file /var/log/caddy/${svc}.log {
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

    # 元数据单独存，避免解析 Caddyfile 注释的脆弱性
    cat > "${META_DIR}/current" << EOF
SVC_NAME=${svc}
DOMAIN=${domain}
BACKEND_IP=${ip}
BACKEND_PORT=${port}
TIMEOUT=${timeout}
EOF

    echo ""
    echo "→ 校验配置..."
    if ! caddy validate --config "$CADDYFILE" --adapter caddyfile 2>&1; then
        echo ""
        echo "[错误] 配置校验失败，未应用。"
        return 1
    fi

    echo "→ 重载 Caddy..."
    systemctl enable caddy >/dev/null 2>&1 || true
    if systemctl is-active --quiet caddy; then
        systemctl reload caddy
    else
        systemctl start caddy
    fi

    echo ""
    echo "已生效。配置: $CADDYFILE"
}

# 读取当前元数据到全局变量
load_meta() {
    if [ ! -f "${META_DIR}/current" ]; then
        return 1
    fi
    # shellcheck disable=SC1091
    source "${META_DIR}/current"
    return 0
}

# ---------- 菜单功能 ----------

generate_caddyfile() {
    clear
    echo "========================================"
    echo "  生成 Caddyfile"
    echo "========================================"
    echo ""

    if [ -f "$CADDYFILE" ]; then
        echo "[提示] 已存在配置: $CADDYFILE"
        echo "继续将覆盖现有配置。"
        echo ""
        read -p "是否继续？[y/N]: " GO
        if [[ ! "$GO" =~ ^[Yy]$ ]]; then
            return
        fi
        echo ""
    fi

    read -p "服务名称 (用于日志文件名，例如 myapp): " SVC_NAME
    [ -z "$SVC_NAME" ] && { echo "[错误] 服务名称不能为空"; pause; return; }

    read -p "域名 (例如 api.example.com): " DOMAIN
    [ -z "$DOMAIN" ] && { echo "[错误] 域名不能为空"; pause; return; }

    echo ""
    read -p "后端 IP [127.0.0.1]: " BACKEND_IP
    BACKEND_IP=${BACKEND_IP:-127.0.0.1}

    echo ""
    read -p "后端端口: " BACKEND_PORT
    [ -z "$BACKEND_PORT" ] && { echo "[错误] 端口不能为空"; pause; return; }

    if ! check_port_in_use "$BACKEND_IP" "$BACKEND_PORT"; then
        pause
        return
    fi

    echo ""
    read -p "超时(秒) [300]: " TIMEOUT
    TIMEOUT=${TIMEOUT:-300}

    if write_and_apply "$SVC_NAME" "$DOMAIN" "$BACKEND_IP" "$BACKEND_PORT" "$TIMEOUT"; then
        echo ""
        echo "========================================"
        echo "  完成"
        echo "========================================"
        echo "  服务: $SVC_NAME"
        echo "  域名: https://$DOMAIN"
        echo "  后端: $BACKEND_IP:$BACKEND_PORT"
        echo "  超时: ${TIMEOUT}s"
        echo "  日志: /var/log/caddy/${SVC_NAME}.log"
    fi
    pause
}

view_caddyfile() {
    clear
    echo "========================================"
    echo "  查看配置"
    echo "========================================"
    echo ""

    if ! load_meta; then
        echo "[错误] 未找到配置元数据。请先用菜单 ① 生成。"
        pause
        return
    fi

    echo "  服务名称: $SVC_NAME"
    echo "  域名:     $DOMAIN"
    echo "  后端 IP:  $BACKEND_IP"
    echo "  后端端口: $BACKEND_PORT"
    echo "  超时:     ${TIMEOUT}s"
    echo ""
    echo "--- $CADDYFILE ---"
    echo ""
    if [ -f "$CADDYFILE" ]; then
        cat "$CADDYFILE"
    else
        echo "[警告] $CADDYFILE 不存在"
    fi
    echo ""
    echo "--- Caddy 服务状态 ---"
    systemctl is-active caddy && echo "running" || echo "stopped"
    pause
}

edit_caddyfile() {
    clear
    echo "========================================"
    echo "  更改配置"
    echo "========================================"
    echo ""

    if ! load_meta; then
        echo "[错误] 未找到配置元数据。请先用菜单 ① 生成。"
        pause
        return
    fi

    echo "  1) 服务名称: $SVC_NAME"
    echo "  2) 域名:     $DOMAIN"
    echo "  3) 后端 IP:  $BACKEND_IP"
    echo "  4) 后端端口: $BACKEND_PORT"
    echo "  5) 超时:     ${TIMEOUT}s"
    echo "  0) 返回"
    echo "========================================"
    echo ""
    read -p "选择要修改的项 [0-5]: " EDIT_CHOICE

    case $EDIT_CHOICE in
        0) return ;;
        1)
            read -p "服务名称 [$SVC_NAME]: " NEW_VAL
            [ -n "$NEW_VAL" ] && SVC_NAME="$NEW_VAL"
            ;;
        2)
            read -p "域名 [$DOMAIN]: " NEW_VAL
            [ -n "$NEW_VAL" ] && DOMAIN="$NEW_VAL"
            ;;
        3)
            read -p "后端 IP [$BACKEND_IP]: " NEW_VAL
            [ -n "$NEW_VAL" ] && BACKEND_IP="$NEW_VAL"
            ;;
        4)
            read -p "后端端口 [$BACKEND_PORT]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then
                if ! check_port_in_use "$BACKEND_IP" "$NEW_VAL"; then
                    pause
                    return
                fi
                BACKEND_PORT="$NEW_VAL"
            fi
            ;;
        5)
            read -p "超时(秒) [$TIMEOUT]: " NEW_VAL
            [ -n "$NEW_VAL" ] && TIMEOUT="$NEW_VAL"
            ;;
        *)
            echo "无效选项"; pause; return
            ;;
    esac

    write_and_apply "$SVC_NAME" "$DOMAIN" "$BACKEND_IP" "$BACKEND_PORT" "$TIMEOUT"
    pause
}

update_caddy() {
    clear
    echo "========================================"
    echo "  更新 Caddy"
    echo "========================================"
    echo ""
    apt update
    apt install --only-upgrade -y caddy
    echo ""
    echo "Caddy 已更新到最新版。"
    pause
}

uninstall_caddy() {
    clear
    echo "========================================"
    echo "  卸载 Caddy"
    echo "========================================"
    echo ""
    echo "这将完全移除 Caddy、配置文件和日志，是否继续？"
    read -p "输入 yes 确认卸载: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "已取消。"
        pause
        return
    fi
    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    apt purge -y caddy 2>/dev/null || true
    rm -rf /etc/caddy /var/log/caddy /var/lib/caddy 2>/dev/null || true
    echo ""
    echo "Caddy 已卸载。"
    pause
}

# ---------- 主循环 ----------

require_root
ensure_caddy_installed

while true; do
    clear
    echo "========================================"
    echo "  Caddy 工具箱"
    echo "========================================"
    echo "  1) 生成 Caddyfile"
    echo "  2) 查看配置"
    echo "  3) 更改配置"
    echo "  4) 更新 Caddy"
    echo "  5) 卸载 Caddy"
    echo "  0) 退出"
    echo "========================================"
    echo ""
    read -p "请选择 [0-5]: " CHOICE

    case $CHOICE in
        1) generate_caddyfile ;;
        2) view_caddyfile ;;
        3) edit_caddyfile ;;
        4) update_caddy ;;
        5) uninstall_caddy ;;
        0) exit 0 ;;
        *) echo "无效选项，按回车重试..."; read ;;
    esac
done
