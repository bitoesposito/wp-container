#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BACKUP_BASE="backup"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

# Load env
if [[ ! -f .env ]]; then
	echo "File .env non trovato. Creare .env con MYSQL_* e WORDPRESS_PORT."
	exit 1
fi
set -a
# shellcheck source=/dev/null
source .env
set +a

echo "=============================================="
echo "  Export backup WordPress (processo guidato)"
echo "=============================================="
echo ""
echo "Cartella di backup: ${BACKUP_DIR}"
echo ""

# Check containers
if ! docker compose ps -q wordpress 2>/dev/null | grep -q .; then
	echo "I container non risultano avviati. Avviare con: docker compose up -d"
	exit 1
fi

mkdir -p "$BACKUP_DIR"

# 1) Database dump
echo "[1/3] Export database..."
docker compose exec -T db mariadb-dump -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" > "${BACKUP_DIR}/db.sql"
echo "      Salvato: ${BACKUP_DIR}/db.sql"

# 2) wp-content
echo "[2/3] Export wp-content (temi, plugin, uploads)..."
if [[ -d wordpress/wp-content ]]; then
	tar -czf "${BACKUP_DIR}/wp-content.tar.gz" -C wordpress wp-content
	echo "      Salvato: ${BACKUP_DIR}/wp-content.tar.gz"
else
	echo "      Attenzione: wordpress/wp-content non trovato, skip."
fi

# 3) File di progetto (senza dati sensibili)
echo "[3/3] Copia docker-compose.yml..."
cp docker-compose.yml "${BACKUP_DIR}/"

# URL del sito (per restore: suggerisce l'URL "vecchio" quando ripristini su altro dominio)
SITEURL_EXPORT=""
SITEURL_EXPORT=$(docker compose exec -T wordpress wp option get siteurl --allow-root 2>/dev/null | tr -d '\r') || true

# Manifest
{
	echo "Backup export: $(date -Iseconds)"
	echo "Cartella: ${BACKUP_DIR}"
	echo "Contenuto: db.sql, wp-content.tar.gz, docker-compose.yml"
	echo "Database: ${MYSQL_DATABASE}"
	[[ -n "$SITEURL_EXPORT" ]] && echo "SITE_URL=${SITEURL_EXPORT}"
} > "${BACKUP_DIR}/manifest.txt"

echo ""
echo "=============================================="
echo "  Export completato: ${BACKUP_DIR}"
echo "=============================================="
echo ""
echo "Per ripristinare: ./restore.sh"
