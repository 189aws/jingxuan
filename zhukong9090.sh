#!/bin/bash
# NodePass Master 改进版 - 解决断网与死锁问题

echo "--- 开始部署 NodePass Master 主控 ---"

# 1. 环境清理：先解锁并恢复 DNS，确保拉取镜像时网络正常
[ -f /etc/resolv.conf.bak ] && cp /etc/resolv.conf.bak /etc/resolv.conf
chattr -i /etc/resolv.conf &>/dev/null
docker rm -f doh-proxy npmaster &>/dev/null

# 2. 预拉取镜像：在 DNS 锁定前完成，防止拉取时报错
echo "正在预拉取必要镜像..."
docker pull cloudflare/cloudflared:latest
docker pull ghcr.io/nodepassproject/nodepass:latest

# 3. 部署 DoH 代理
echo "正在启动 DoH 代理..."
docker run -d \
  --name=doh-proxy \
  --restart=always \
  -p 127.0.0.1:53:53/udp \
  cloudflare/cloudflared:latest \
  proxy-dns --address 0.0.0.0 --port 53 --upstream https://1.1.1.2/dns-query

# 4. 稳健的 DNS 切换逻辑
echo "等待代理就绪..."
sleep 5 # 给容器启动留出时间

echo "正在优化系统 DNS 配置..."
# 不再完全禁用服务，而是修改 resolv.conf 顺序
# 将 127.0.0.1 放在首行，保留原 DNS 作为备选以防断网
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 1.1.1.2
nameserver 8.8.8.8
EOF

# 5. 启动主控
mkdir -p /root/nodepass-master/nodepass-master-data
cd /root/nodepass-master

cat > docker-compose.yml <<EOF
services:
  npmaster:
    image: ghcr.io/nodepassproject/nodepass:latest
    container_name: npmaster
    # host 模式会继承宿主机的 resolv.conf
    command:
      - master://0.0.0.0:9090?log=info&tls=1
    network_mode: host
    volumes:
      - ./nodepass-master-data:/gob
    restart: unless-stopped
EOF

docker compose up -d

echo "------------------------------------------------"
echo "部署完成！"
echo "API Key 提取中..."
sleep 5
API_KEY=$(docker logs npmaster 2>&1 | grep "API Key created" | awk '{print $NF}')
echo "你的 API Key 是: ${API_KEY:-'无法获取，请检查日志'}"
echo "------------------------------------------------"