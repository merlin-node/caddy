#!/bin/bash
# Caddy 反向代理配置生成脚本 (Debian/Ubuntu)
#===================================
# 一键安装:
#   wget -O ca https://raw.githubusercontent.com/merlin-node/caddy/main/setup-caddy.sh && chmod +x ca && sudo mv ca /usr/local/bin/ca
# 之后在 VPS 里直接输入 ca 即可运行
#===================================

set -e

SCRIPT_PATH="$(realpath "$0")"

# 生成 Caddyfile
generate_caddyfile() {
    clear
    echo "========================================"
    echo "  生成 Caddyfile"
    echo "========================================"
    echo ""

    read -p "服务名称 (用于日志文件名，例如 myapp): " SVC_NAME
    if [ -z "$SVC_NAME" ]; then
        echo ""
        echo "[错误] 服务名称不能为空"
        read -p "按回车返回主菜单..."
        return
    fi

    read -p "请输入你的域名 (例如 api.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo ""
        echo "[错误] 域名不能为空"
        read -p "按回车返回主菜单..."
        return
    fi

    echo ""
    echo "后端服务 IP 地址？直接回车使用默认值 127.0.0.1"
    read -p "后端 IP [127.0.0.1]: " BACKEND_IP
    BACKEND_IP=${BACKEND_IP:-127.0.0.1}

    echo ""
    read -p "后端端口: " BACKEND_PORT
    if [ -z "$BACKEND_PORT" ]; then
        echo ""
        echo "[错误] 端口不能为空"
        read -p "按回车返回主菜单..."
        return
    fi
    if ss -tlnp | grep -q ":${BACKEND_PORT} "; then
        echo ""
        echo "[错误] 端口 ${BACKEND_PORT} 已被占用:"
        ss -tlnp | grep ":${BACKEND_PORT} "
        read -p "按回车返回主菜单..."
        return
    fi

    echo ""
    echo "反向代理超时时间(秒)？直接回车使用默认值 300"
    read -p "超时(秒) [300]: " TIMEOUT
    TIMEOUT=${TIMEOUT:-300}

    cat > Caddyfile << EOF
# Caddyfile for ${SVC_NAME}
# 域名: ${DOMAIN}
# 后端: ${BACKEND_IP}:${BACKEND_PORT}
# 超时: ${TIMEOUT}s

${DOMAIN} {
    log {
        output file /var/log/caddy/${SVC_NAME}.log {
            roll_size 10mb
            roll_keep 5
        }
    }

    reverse_proxy ${BACKEND_IP}:${BACKEND_PORT} {
        transport http {
            read_timeout ${TIMEOUT}s
            write_timeout ${TIMEOUT}s
        }

        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

    echo ""
    echo "========================================"
    echo "  配置已生成: $(pwd)/Caddyfile"
    echo "========================================"
    echo ""
    cat Caddyfile
    echo ""
    echo "运行命令: caddy run --config $(pwd)/Caddyfile"
    echo ""
    read -p "按回车返回主菜单..."
}

# 更新 Caddy
update_caddy() {
    clear
    echo "========================================"
    echo "  更新 Caddy"
    echo "========================================"
    echo ""
    sudo apt update
    sudo apt upgrade -y caddy
    echo ""
    echo "Caddy 已更新到最新版。"
    echo ""
    read -p "按回车返回主菜单..."
}

# 卸载 Caddy
uninstall_caddy() {
    clear
    echo "========================================"
    echo "  卸载 Caddy"
    echo "========================================"
    echo ""
    echo "这将完全移除 Caddy 及其配置文件，是否继续？"
    read -p "输入 yes 确认卸载: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "已取消。"
        read -p "按回车返回主菜单..."
        return
    fi
    echo ""
    sudo systemctl stop caddy 2>/dev/null || true
    sudo systemctl disable caddy 2>/dev/null || true
    sudo apt purge -y caddy 2>/dev/null || true
    sudo rm -rf /etc/caddy /var/log/caddy /var/lib/caddy 2>/dev/null || true
    echo ""
    echo "Caddy 已卸载。"
    echo ""
    read -p "按回车返回主菜单..."
}

# 查看配置
view_caddyfile() {
    clear
    echo "========================================"
    echo "  查看配置"
    echo "========================================"
    echo ""

    if [ ! -f "Caddyfile" ]; then
        echo "[错误] 当前目录未找到 Caddyfile"
        read -p "按回车返回主菜单..."
        return
    fi

    SVC_NAME=$(grep "^# Caddyfile for " Caddyfile | sed 's/# Caddyfile for //')
    DOMAIN=$(grep "^# 域名: " Caddyfile | sed 's/# 域名: //')
    BACKEND_IP=$(grep "^# 后端: " Caddyfile | sed 's/# 后端: //' | cut -d: -f1)
    BACKEND_PORT=$(grep "^# 后端: " Caddyfile | sed 's/# 后端: //' | cut -d: -f2)
    TIMEOUT=$(grep "^# 超时: " Caddyfile | sed 's/# 超时: //' | sed 's/s$//')

    echo "  服务名称: $SVC_NAME"
    echo "  域名:     $DOMAIN"
    echo "  后端 IP:  $BACKEND_IP"
    echo "  后端端口: $BACKEND_PORT"
    echo "  超时:     ${TIMEOUT}s"
    echo ""
    echo "--- Caddyfile 内容 ---"
    echo ""
    cat Caddyfile
    echo ""
    read -p "按回车返回主菜单..."
}

# 更改配置
edit_caddyfile() {
    clear
    echo "========================================"
    echo "  更改配置"
    echo "========================================"
    echo ""

    if [ ! -f "Caddyfile" ]; then
        echo "[错误] 当前目录未找到 Caddyfile"
        read -p "按回车返回主菜单..."
        return
    fi

    SVC_NAME=$(grep "^# Caddyfile for " Caddyfile | sed 's/# Caddyfile for //')
    DOMAIN=$(grep "^# 域名: " Caddyfile | sed 's/# 域名: //')
    BACKEND_IP=$(grep "^# 后端: " Caddyfile | sed 's/# 后端: //' | cut -d: -f1)
    BACKEND_PORT=$(grep "^# 后端: " Caddyfile | sed 's/# 后端: //' | cut -d: -f2)
    TIMEOUT=$(grep "^# 超时: " Caddyfile | sed 's/# 超时: //' | sed 's/s$//')

    echo "  ① 服务名称: $SVC_NAME"
    echo "  ② 域名:     $DOMAIN"
    echo "  ③ 后端 IP:  $BACKEND_IP"
    echo "  ④ 后端端口: $BACKEND_PORT"
    echo "  ⑤ 超时:     ${TIMEOUT}s"
    echo "  0 返回"
    echo "========================================"
    echo ""
    read -p "选择要修改的项 [0-5]: " EDIT_CHOICE

    case $EDIT_CHOICE in
        0) return ;;
        1)
            echo ""
            read -p "服务名称 [$SVC_NAME]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then SVC_NAME="$NEW_VAL"; fi
            ;;
        2)
            echo ""
            read -p "域名 [$DOMAIN]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then DOMAIN="$NEW_VAL"; fi
            ;;
        3)
            echo ""
            read -p "后端 IP [$BACKEND_IP]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then BACKEND_IP="$NEW_VAL"; fi
            ;;
        4)
            echo ""
            read -p "后端端口 [$BACKEND_PORT]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then
                if ss -tlnp | grep -q ":${NEW_VAL} "; then
                    echo ""
                    echo "[错误] 端口 ${NEW_VAL} 已被占用:"
                    ss -tlnp | grep ":${NEW_VAL} "
                    read -p "按回车返回..."
                    return
                fi
                BACKEND_PORT="$NEW_VAL"
            fi
            ;;
        5)
            echo ""
            read -p "超时(秒) [$TIMEOUT]: " NEW_VAL
            if [ -n "$NEW_VAL" ]; then TIMEOUT="$NEW_VAL"; fi
            ;;
        *)
            echo "无效选项，按回车返回..."; read
            return
            ;;
    esac

    cat > Caddyfile << EOF
# Caddyfile for ${SVC_NAME}
# 域名: ${DOMAIN}
# 后端: ${BACKEND_IP}:${BACKEND_PORT}
# 超时: ${TIMEOUT}s

${DOMAIN} {
    log {
        output file /var/log/caddy/${SVC_NAME}.log {
            roll_size 10mb
            roll_keep 5
        }
    }

    reverse_proxy ${BACKEND_IP}:${BACKEND_PORT} {
        transport http {
            read_timeout ${TIMEOUT}s
            write_timeout ${TIMEOUT}s
        }

        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    echo ""
    echo "已更新。"
    read -p "按回车返回主菜单..."
}

# 主菜单
while true; do
    clear
    echo "========================================"
    echo "  Caddy 工具箱"
    echo "========================================"
    echo "  ① 生成 Caddyfile"
    echo "  ② 查看配置"
    echo "  ③ 更改配置"
    echo "  ④ 更新 Caddy"
    echo "  ⑤ 卸载 Caddy"
    echo "  ⑥ 退出"
    echo "========================================"
    echo ""
    read -p "请选择 [1-6]: " CHOICE

    case $CHOICE in
        1) generate_caddyfile ;;
        2) view_caddyfile ;;
        3) edit_caddyfile ;;
        4) update_caddy ;;
        5) uninstall_caddy ;;
        6) exit 0 ;;
        *) echo "无效选项，按回车重试..."; read ;;
    esac
done
