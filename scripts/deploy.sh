#!/usr/bin/env bash
# Llamado por GitHub Actions via SSH para actualizar un servicio.
# Uso: bash deploy.sh <web|api|admin|infra>
set -euo pipefail

SERVICE="${1:?Uso: deploy.sh <web|api|admin|infra>}"
TAG="${2:-latest}"
DEPLOY_DIR="/opt/habitame"

cd "$DEPLOY_DIR"

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Deploy iniciado: $SERVICE ($TAG)"

case "$SERVICE" in
  web|api|admin)
    IMAGE="ghcr.io/habitame/habitame-${SERVICE}:${TAG}"
    docker pull "$IMAGE"
    docker tag "$IMAGE" "ghcr.io/habitame/habitame-${SERVICE}:latest"
    docker compose up -d --no-deps "$SERVICE"
    docker image prune -f
    ;;
  infra)
    git pull origin main
    docker compose up -d
    docker compose exec nginx nginx -s reload 2>/dev/null || true
    docker image prune -f
    ;;
  *)
    echo "Servicio desconocido: $SERVICE. Válidos: web, api, admin, infra"
    exit 1
    ;;
esac

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Deploy $SERVICE completado"
