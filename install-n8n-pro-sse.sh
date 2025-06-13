#!/bin/bash
set -e

echo "🚀 INSTALADOR PRO de n8n + Webhook + MCP + SSL + NGINX MACHÍN"
IP=$(curl -s https://api.ipify.org)
echo "🌐 IP detectada: $IP"
echo "👉 Asegúrate de que tu dominio A apunte a esta IP."

read -p "🌐 Dominio para n8n (ej: n8n.humandnet.com): " DOMINIO
read -p "📧 Email para SSL (Let's Encrypt): " EMAIL

apt update -y && apt upgrade -y
apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx ufw fail2ban curl unzip ca-certificates gnupg lsb-release

systemctl enable docker --now
systemctl enable nginx --now

ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

mkdir -p /opt/n8n
cd /opt/n8n

echo "🔍 Verificando instalación previa de n8n..."
if docker ps -a --format '{{.Names}}' | grep -q n8n-app; then
  echo "🧨 Contenedor anterior detectado. Eliminando..."
  docker-compose down -v || true
  docker rm -f n8n-app || true
fi

if [ -d "./n8n_data" ]; then
  echo "🧹 Eliminando datos previos..."
  rm -rf ./n8n_data
fi

mkdir -p ./n8n_data
chown -R 1000:1000 ./n8n_data

cat <<ENV > .env
N8N_HOST=$DOMINIO
N8N_PORT=5678
WEBHOOK_URL=https://$DOMINIO/
N8N_PROTOCOL=https
VUE_APP_URL_BASE_API=https://$DOMINIO/
N8N_BASIC_AUTH_ACTIVE=false
N8N_DIAGNOSTICS_ENABLED=false
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true
ENV

cat <<YML > docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-app
    restart: always
    env_file:
      - .env
    ports:
      - "5678:5678"
    volumes:
      - ./n8n_data:/home/node/.n8n
YML

docker-compose up -d --force-recreate

cat <<HTTP > /etc/nginx/sites-available/$DOMINIO
server {
    listen 80;
    server_name $DOMINIO;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
HTTP

ln -sf /etc/nginx/sites-available/$DOMINIO /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

certbot certonly --nginx -d $DOMINIO --non-interactive --agree-tos -m $EMAIL

cat <<HTTPS > /etc/nginx/sites-available/$DOMINIO
server {
    listen 80;
    server_name $DOMINIO;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMINIO;

    ssl_certificate /etc/letsencrypt/live/$DOMINIO/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMINIO/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # 🔥 Soporte SSE para /mcp/
    location /mcp/ {
        proxy_pass http://localhost:5678/mcp/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Accept-Encoding '';
        chunked_transfer_encoding off;
    }
}
HTTPS

nginx -t && systemctl reload nginx
docker-compose restart

echo ""
echo "✅ INSTALACIÓN COMPLETA CON SOPORTE SSE: https://$DOMINIO"
