#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKUP_BASE="backup"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

if [[ ! -f .env ]]; then
	echo ".env file not found. Create .env with MYSQL_* and WORDPRESS_PORT."
	exit 1
fi
set -a
# shellcheck source=/dev/null
source .env
set +a

echo "=============================================="
echo "  WordPress backup export (guided)"
echo "=============================================="
echo ""
echo "Backup directory: ${BACKUP_DIR}"
echo ""

if ! docker compose ps -q wordpress 2>/dev/null | grep -q .; then
	echo "Containers are not running. Start them with: docker compose up -d"
	exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[1/3] Export database..."
docker compose exec -T db mariadb-dump -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" > "${BACKUP_DIR}/db.sql"
echo "      Saved: ${BACKUP_DIR}/db.sql"

echo "[2/3] Export wp-content (themes, plugins, uploads)..."
if [[ -d wordpress/wp-content ]]; then
	tar -czf "${BACKUP_DIR}/wp-content.tar.gz" -C wordpress wp-content
	echo "      Saved: ${BACKUP_DIR}/wp-content.tar.gz"
else
	echo "      Warning: wordpress/wp-content not found, skipping."
fi

echo "[3/3] Copy docker-compose.yml..."
cp docker-compose.yml "${BACKUP_DIR}/"

SITEURL_EXPORT=""
SITEURL_EXPORT=$(docker compose exec -T wordpress wp option get siteurl --allow-root 2>/dev/null | tr -d '\r') || true

{
	echo "Backup export: $(date -Iseconds)"
	echo "Directory: ${BACKUP_DIR}"
	echo "Content: db.sql, wp-content.tar.gz, docker-compose.yml"
	echo "Database: ${MYSQL_DATABASE}"
	[[ -n "$SITEURL_EXPORT" ]] && echo "SITE_URL=${SITEURL_EXPORT}"
} > "${BACKUP_DIR}/manifest.txt"

echo ""
echo "=============================================="
echo "  Export completed: ${BACKUP_DIR}"
echo "=============================================="
echo ""
echo "To restore: ./scripts/restore.sh"

