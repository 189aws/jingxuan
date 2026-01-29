#!/bin/bash

# ==========================================
# 1. 自定义配置区
# ==========================================
# Telegram 配置
TG_TOKEN="7756669471:AAFstxnzCweHItNptwOf7UU-p6xj3pwnAI8"
TG_CHAT_ID="1792396794"

# 节点配置 (SS 2022 要求密码必须是特定长度的 Base64 字符串)
SS_PORT=10888
# 这里的密码是 16 字节(128bit)的 Base64，适合 aes-128-gcm
SS_PASSWORD="vPz9A8jK7mN4Q2xR5tW1uA==" 
SS_METHOD="2022-blake3-aes-128-gcm"
DOH_URL="https://1.1.1.2/dns-query"

# ==========================================
# 2. 基础环境安装
# ==========================================
echo "正在安装基础环境..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl jq docker.io docker-compose
sudo systemctl enable --now docker

# 开启内核转发
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# ==========================================
# 3. 部署目录
# ==========================================
mkdir -p ~/ss_isolated
cd ~/ss_isolated

# ==========================================
# 4. 生成 sing-box 配置 (Shadowsocks)
# ==========================================
cat <<EOT > config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [{ "tag": "dns-remote", "address": "$DOH_URL", "detour": "direct" }],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $SS_PORT,
      "method": "$SS_METHOD",
      "password": "$SS_PASSWORD"
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOT

# 写入 docker-compose.yml
cat <<EOT > docker-compose.yml
version: '3'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: ss-isolated
    restart: always
    ports:
      - "$SS_PORT:$SS_PORT/tcp"
      - "$SS_PORT:$SS_PORT/udp"
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# ==========================================
# 5. 启动服务
# ==========================================
if docker compose version >/dev/null 2>&1; then
    docker compose down 2>/dev/null && docker compose up -d
else
    docker-compose down 2>/dev/null && docker-compose up -d
fi

# ==========================================
# 6. 生成链接与推送
# ==========================================
IP=$(curl -s https://api64.ipify.org)
# 构造 SS 链接 (SS2022 格式)
RAW_LINK="ss://$(echo -n "$SS_METHOD:$SS_PASSWORD" | base64 -w 0)@$IP:$SS_PORT#SingBox_SS_$IP"

# VPS 本地终端输出
echo "-------------------------------------------------------"
echo "✅ Shadowsocks 部署完成！"
echo "本地留存链接: $RAW_LINK"
echo "-------------------------------------------------------"

# Telegram 只发送链接
echo "正在推送链接至 Telegram..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$RAW_LINK")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "✅ 推送成功！"
else
    echo "❌ 推送失败，详情: $RESPONSE"
fi