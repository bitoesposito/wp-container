#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BACKUP_BASE="backup"

echo "=============================================="
echo "  WordPress backup restore"
echo "=============================================="
echo ""

if [[ ! -d "$BACKUP_BASE" ]]; then
	echo "Directory ${BACKUP_BASE}/ not found. Run scripts/export.sh first."
	exit 1
fi

BACKUPS=()
for d in "$BACKUP_BASE"/*/; do
	[[ -z "$d" ]] && continue
	dir="${d%/}"
	[[ -f "${dir}/db.sql" ]] && BACKUPS+=("$dir")
done
mapfile -t BACKUPS < <(printf '%s\n' "${BACKUPS[@]}" | sort -r)

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
	echo "Nessun backup valido in ${BACKUP_BASE}/ (atteso db.sql in una sottocartella)."
	exit 1
fi

echo "Available backups:"
for i in "${!BACKUPS[@]}"; do
	echo "  $((i + 1))) ${BACKUPS[$i]##*/}"
done
echo "  0) Exit"
echo ""
read -r -p "Which backup do you want to restore? (number): " CHOICE

if [[ "$CHOICE" == "0" ]]; then
	echo "Operation cancelled."
	exit 0
fi

if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#BACKUPS[@]} )); then
	echo "Invalid choice."
	exit 1
fi

RESTORE_DIR="${BACKUPS[$((CHOICE - 1))]}"
echo ""
echo "Restoring from: $RESTORE_DIR"
echo ""

if [[ ! -f .env ]]; then
	echo ".env file not found. Copy .env.example to .env and configure MySQL/WordPress variables before running the restore."
	exit 1
fi

set -a
# shellcheck source=/dev/null
source .env
set +a

MISSING_VAR=0
for var in MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD MYSQL_ROOT_PASSWORD; do
	if [[ -z "${!var:-}" ]]; then
		echo "Variable ${var} is not set in .env"
		MISSING_VAR=1
	fi
done

if [[ "$MISSING_VAR" -ne 0 ]]; then
	echo "Configure the .env file correctly before proceeding."
	exit 1
fi

# URL: vecchio (backup) vs nuovo (ambiente attuale)
OLD_URL_FROM_MANIFEST=""
if [[ -f "${RESTORE_DIR}/manifest.txt" ]]; then
	OLD_URL_FROM_MANIFEST=$(grep -E '^SITE_URL=' "${RESTORE_DIR}/manifest.txt" 2>/dev/null | cut -d= -f2- | tr -d '\r')
fi

DEFAULT_NEW_URL=""
if [[ -n "${SITE_URL:-}" ]]; then
	DEFAULT_NEW_URL="$SITE_URL"
else
	DEFAULT_NEW_URL="http://localhost:${WORDPRESS_PORT:-8080}"
fi

echo ""
echo "--- Site URL ---"
echo "If you are restoring to a different domain/port, provide the old and new URLs."
if [[ -n "$OLD_URL_FROM_MANIFEST" ]]; then
	echo "  Detected in backup: ${OLD_URL_FROM_MANIFEST}"
	read -r -p "Old URL (Enter = use detected, leave empty to skip search-replace): " OLD_URL_INPUT
	OLD_URL="${OLD_URL_INPUT:-$OLD_URL_FROM_MANIFEST}"
else
	read -r -p "Old URL (leave empty to skip search-replace): " OLD_URL
fi

NEW_URL=""
if [[ -n "$OLD_URL" ]]; then
	read -r -p "New URL [${DEFAULT_NEW_URL}]: " NEW_URL_INPUT
	NEW_URL="${NEW_URL_INPUT:-$DEFAULT_NEW_URL}"
fi

echo ""
echo "[1/5] Starting database..."
docker compose up -d db
sleep 5

echo "[2/5] Preparing WordPress volume..."
docker compose up -d wordpress 2>/dev/null || true
docker compose stop wordpress 2>/dev/null || true

if [[ -f "${RESTORE_DIR}/wp-content.tar.gz" ]]; then
	echo "[3/5] Restoring wp-content..."
	BACKUP_ABS="${ROOT_DIR}/${RESTORE_DIR}"
	docker compose run --rm \
		-v "${BACKUP_ABS}:/backup:ro" \
		wordpress \
		sh -c "rm -rf /var/www/html/wp-content && tar -xzf /backup/wp-content.tar.gz -C /var/www/html"
	HOST_UID=$(id -u)
	docker compose run --rm --user root -e HOST_UID="$HOST_UID" wordpress \
		sh -c "chown -R \${HOST_UID}:33 /var/www/html/wp-content && chmod -R g+rwX /var/www/html/wp-content && find /var/www/html/wp-content -type d -exec chmod g+s {} \;"
else
	echo "[3/5] wp-content.tar.gz missing, skipping."
fi

echo "[4/5] Importing database..."
docker compose exec -T db mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`; CREATE DATABASE \`${MYSQL_DATABASE}\`;"
docker compose exec -T db mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < "${RESTORE_DIR}/db.sql"

echo "[5/5] Starting WordPress and running URL search-replace..."
docker compose up -d wordpress
sleep 5

if [[ -n "${OLD_URL:-}" && -n "${NEW_URL:-}" ]]; then
	if docker compose --profile tools run --rm \
		-e WORDPRESS_DB_HOST=db \
		-e WORDPRESS_DB_USER="${MYSQL_USER}" \
		-e WORDPRESS_DB_PASSWORD="${MYSQL_PASSWORD}" \
		-e WORDPRESS_DB_NAME="${MYSQL_DATABASE}" \
		wpcli search-replace "$OLD_URL" "$NEW_URL" --all-tables --allow-root 2>/dev/null; then
		:
	else
		echo "      Search-replace failed. Update siteurl/home in Settings > General."
	fi
fi

FINAL_URL="${SITE_URL:-http://localhost:${WORDPRESS_PORT:-8080}}"

echo ""
echo "=============================================="
echo "  Restore completed."
echo "=============================================="
echo ""
echo "Site: ${FINAL_URL}"
echo ""

