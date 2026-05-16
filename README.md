# Caddy 反向代理配置生成器

交互式生成 Caddy 反向代理配置文件，适合 Debian/Ubuntu VPS。

## 一键安装

```bash
wget -O ca https://raw.githubusercontent.com/merlin-node/caddy/main/setup-caddy.sh && chmod +x ca && sudo mv ca /usr/local/bin/ca
```

## 使用

安装后在终端输入：

```bash
ca
```

按提示依次输入服务名称、域名、后端 IP、端口、超时时间（每步均可直接回车使用默认值），脚本会在当前目录生成 `Caddyfile`。

## 运行 Caddy

```bash
caddy run --config Caddyfile
```

## 默认值

| 配置项   | 默认值       |
| -------- | ------------ |
| 后端 IP  | 127.0.0.1    |
| 后端端口 | 8080         |
| 超时     | 300 秒       |
