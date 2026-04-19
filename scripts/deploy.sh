#!/usr/bin/env bash
# Llamado por GitHub Actions via SSH para actualizar un servicio.
# Uso: bash deploy.sh <web|api|infra>
set -euo pipefail

SERVICE="${1:?Uso: deploy.sh <web|api|infra>}"
DEPLOY_DIR="/opt/habitame"

cd "$DEPLOY_DIR"

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Deploy iniciado: $SERVICE"

case "$SERVICE" in
  web|api)
    docker compose pull "$SERVICE"
    docker compose up -d --no-deps "$SERVICE"
    docker image prune -f
    ;;
  infra)
    git pull origin main
    docker compose exec nginx nginx -t
    docker compose exec nginx nginx -s reload
    docker compose up -d
    docker image prune -f
    ;;
  *)
    echo "Servicio desconocido: $SERVICE. Válidos: web, api, infra"
    exit 1
    ;;
esac

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Deploy $SERVICE completado"
