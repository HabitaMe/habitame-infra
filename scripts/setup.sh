#!/usr/bin/env bash
# Ejecutar una sola vez en un VPS Ubuntu 22.04/24.04 limpio.
# Uso: sudo bash setup.sh <tu-github-user-o-org> <public-ssh-key>
# Ejemplo: sudo bash setup.sh HabitaMe "ssh-ed25519 AAAA..."
set -euo pipefail

GITHUB_ORG="${1:?Falta el nombre de la org/usuario de GitHub (ej: HabitaMe)}"
DEPLOY_SSH_KEY="${2:?Falta la clave SSH pública del usuario deploy}"
DEPLOY_DIR="/opt/habitame"
DEPLOY_USER="deploy"
DOMAIN="habitame.xyz"
EMAIL="danielamores006@gmail.com"

echo "==> [1/9] Actualizando paquetes e instalando dependencias..."
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-plugin git curl ufw

systemctl enable docker
systemctl start docker

echo "==> [2/9] Configurando firewall UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable

echo "==> [3/9] Creando usuario '$DEPLOY_USER'..."
if ! id "$DEPLOY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"

mkdir -p "/home/$DEPLOY_USER/.ssh"
echo "$DEPLOY_SSH_KEY" > "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"

echo "==> [4/9] Clonando habitame-infra en $DEPLOY_DIR..."
mkdir -p "$DEPLOY_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"

if [ -d "$DEPLOY_DIR/.git" ]; then
    echo "    Ya existe, haciendo git pull..."
    su - "$DEPLOY_USER" -c "cd $DEPLOY_DIR && git pull origin main"
else
    su - "$DEPLOY_USER" -c "git clone https://github.com/$GITHUB_ORG/habitame-infra.git $DEPLOY_DIR"
fi

echo "==> [5/9] Verificando archivo .env..."
if [ ! -f "$DEPLOY_DIR/.env" ]; then
    echo ""
    echo "  ATENCIÓN: Crea el archivo .env antes de continuar:"
    echo "  cp $DEPLOY_DIR/.env.example $DEPLOY_DIR/.env"
    echo "  nano $DEPLOY_DIR/.env"
    echo ""
    read -rp "  Presiona ENTER cuando hayas creado y rellenado el .env..."
fi

echo "==> [6/9] Iniciando Nginx en modo HTTP (para ACME challenge)..."
cd "$DEPLOY_DIR"

# Config temporal HTTP-only para que certbot pueda validar
cat > /tmp/habitame-http-only.conf << 'NGINX_HTTP'
server {
    listen 80;
    server_name habitame.xyz www.habitame.xyz api.habitame.xyz uploads.habitame.xyz;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
NGINX_HTTP

docker run -d --name habitame-nginx-temp \
    -p 80:80 \
    -v /tmp/habitame-http-only.conf:/etc/nginx/conf.d/default.conf:ro \
    -v habitame_certbot_www:/var/www/certbot \
    nginx:1.27-alpine || true

sleep 3

echo "==> [7/9] Obteniendo certificados SSL con Let's Encrypt..."
docker run --rm \
    -v habitame_certbot_certs:/etc/letsencrypt \
    -v habitame_certbot_www:/var/www/certbot \
    certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        -d "www.$DOMAIN" \
        -d "api.$DOMAIN" \
        -d "uploads.$DOMAIN"

docker stop habitame-nginx-temp && docker rm habitame-nginx-temp || true

echo "==> [8/9] Iniciando el stack completo..."
cd "$DEPLOY_DIR"
docker compose up -d

echo "==> [9/9] Configurando renovación automática de certificados..."
cat > /etc/cron.d/habitame-certbot-renew << 'CRON'
0 0 * * * root docker run --rm \
    -v habitame_certbot_certs:/etc/letsencrypt \
    -v habitame_certbot_www:/var/www/certbot \
    certbot/certbot renew --quiet \
    && docker exec habitame-nginx nginx -s reload
CRON
chmod 644 /etc/cron.d/habitame-certbot-renew

echo ""
echo "✓ Setup completado. El stack está corriendo en https://$DOMAIN"
echo ""
echo "Secrets de GitHub a configurar en cada repo (habitame-web, habitame-api, habitame-infra):"
echo "  VPS_HOST   = $(curl -s ifconfig.me)"
echo "  VPS_USER   = $DEPLOY_USER"
echo "  VPS_SSH_KEY = (la clave privada correspondiente a la pública que pasaste)"
