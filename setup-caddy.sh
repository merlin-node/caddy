#!/bin/bash
# Caddy 反向代理配置生成脚本 (Debian/Ubuntu)
#===================================
# 一键安装:
#   wget -O ca https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/setup-caddy.sh && chmod +x ca && sudo mv ca /usr/local/bin/ca
# 之后在 VPS 里直接输入 ca 即可运行
#===================================

set -e

echo "========================================"
echo "  Caddy 反向代理配置生成器"
echo "========================================"
echo ""

# 第一步：输入服务名称
read -p "服务名称 (用于日志文件名，例如 myapp): " SVC_NAME

# 第二步：输入域名
read -p "请输入你的域名 (例如 api.example.com): " DOMAIN

# 第三步：输入后端 IP
echo ""
echo "后端服务运行在哪个地址？直接回车使用默认值 127.0.0.1"
read -p "后端 IP [127.0.0.1]: " BACKEND_IP
BACKEND_IP=${BACKEND_IP:-127.0.0.1}

# 第四步：输入后端端口
echo ""
echo "后端服务运行在哪个端口？直接回车使用默认值 8080"
read -p "后端端口 [8080]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-8080}

# 第五步：输入超时时间
echo ""
echo "反向代理超时时间(秒)？直接回车使用默认值 300"
read -p "超时(秒) [300]: " TIMEOUT
TIMEOUT=${TIMEOUT:-300}

# 生成 Caddyfile
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
echo "部署步骤:"
echo "  1. 确保域名 DNS 已解析到服务器 IP"
echo "  2. 运行: caddy run --config $(pwd)/Caddyfile"
echo ""

# 安装快捷命令
SCRIPT_PATH="$(realpath "$0")"
if [ "$(basename "$0")" != "ca" ] && [ "$(basename "$0")" != "fd" ]; then
    echo "是否安装快捷命令？之后在终端输入 ca 即可直接运行本脚本"
    read -p "安装快捷命令 ca ? [y/N]: " INSTALL_ALIAS
    if [ "$INSTALL_ALIAS" = "y" ] || [ "$INSTALL_ALIAS" = "Y" ]; then
        sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/ca
        echo ""
        echo "已安装! 下次直接输入 ca 即可运行。"
    fi
fi
