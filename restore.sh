#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
BACKUP_BASE="backup"

echo "=============================================="
echo "  Restore backup WordPress"
echo "=============================================="
echo ""

if [[ ! -d "$BACKUP_BASE" ]]; then
	echo "Cartella ${BACKUP_BASE}/ non trovata. Eseguire prima export.sh."
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

echo "Backup disponibili:"
for i in "${!BACKUPS[@]}"; do
	echo "  $((i + 1))) ${BACKUPS[$i]##*/}"
done
echo "  0) Esci"
echo ""
read -r -p "Quale backup ripristinare? (numero): " CHOICE

if [[ "$CHOICE" == "0" ]]; then
	echo "Operazione annullata."
	exit 0
fi

if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#BACKUPS[@]} )); then
	echo "Scelta non valida."
	exit 1
fi

RESTORE_DIR="${BACKUPS[$((CHOICE - 1))]}"
echo ""
echo "Ripristino da: $RESTORE_DIR"
echo ""

if [[ -f .env ]]; then
	echo "Trovato .env."
	read -r -p "Usare credenziali DB da .env? (s/n, default s): " USE_ENV
	USE_ENV="${USE_ENV:-s}"
else
	USE_ENV="n"
fi

if [[ "$USE_ENV" == "s" || "$USE_ENV" == "S" ]]; then
	set -a
	# shellcheck source=/dev/null
	source .env
	set +a
else
	read -r -p "MYSQL_DATABASE (default wordpress): " MYSQL_DATABASE
	MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
	read -r -p "MYSQL_USER (default wordpress): " MYSQL_USER
	MYSQL_USER="${MYSQL_USER:-wordpress}"
	read -r -s -p "MYSQL_PASSWORD: " MYSQL_PASSWORD
	echo ""
	read -r -s -p "MYSQL_ROOT_PASSWORD: " MYSQL_ROOT_PASSWORD
	echo ""
	export MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD MYSQL_ROOT_PASSWORD
fi

# URL: vecchio (backup) vs nuovo (ambiente attuale)
OLD_URL_FROM_MANIFEST=""
[[ -f "${RESTORE_DIR}/manifest.txt" ]] && OLD_URL_FROM_MANIFEST=$(grep -E '^SITE_URL=' "${RESTORE_DIR}/manifest.txt" 2>/dev/null | cut -d= -f2- | tr -d '\r')

if [[ "$USE_ENV" != "s" && "$USE_ENV" != "S" ]] && [[ -f .env ]]; then
	val=$(grep -E '^SITE_URL=' .env 2>/dev/null | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' | tr -d '\r')
	[[ -n "$val" ]] && SITE_URL="$val"
	val=$(grep -E '^WORDPRESS_PORT=' .env 2>/dev/null | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' | tr -d '\r')
	[[ -n "$val" ]] && WORDPRESS_PORT="$val"
fi
DEFAULT_NEW_URL="${SITE_URL:-http://localhost:${WORDPRESS_PORT:-8080}}"

echo ""
echo "--- URL sito ---"
echo "Se ripristini su un altro dominio/porta, indica URL vecchio e nuovo."
if [[ -n "$OLD_URL_FROM_MANIFEST" ]]; then
	echo "  Rilevato nel backup: ${OLD_URL_FROM_MANIFEST}"
	read -r -p "URL vecchio (Invio = usa rilevato): " OLD_URL_INPUT
	OLD_URL="${OLD_URL_INPUT:-$OLD_URL_FROM_MANIFEST}"
else
	read -r -p "URL vecchio (lascia vuoto per saltare): " OLD_URL
fi
NEW_URL=""
if [[ -n "$OLD_URL" ]]; then
	read -r -p "URL nuovo [${DEFAULT_NEW_URL}]: " NEW_URL_INPUT
	NEW_URL="${NEW_URL_INPUT:-$DEFAULT_NEW_URL}"
fi

echo ""
echo "[1/5] Avvio stack..."
docker compose up -d db
sleep 5
docker compose up -d wordpress 2>/dev/null || true

echo "[2/5] Arresto WordPress..."
docker compose stop wordpress 2>/dev/null || true

if [[ -f "${RESTORE_DIR}/wp-content.tar.gz" ]]; then
	echo "[3/5] Ripristino wp-content..."
	BACKUP_ABS="${SCRIPT_DIR}/${RESTORE_DIR}"
	docker compose run --rm \
		-v "${BACKUP_ABS}:/backup:ro" \
		wordpress \
		sh -c "rm -rf /var/www/html/wp-content && tar -xzf /backup/wp-content.tar.gz -C /var/www/html"
	HOST_UID=$(id -u)
	docker compose run --rm --user root -e HOST_UID="$HOST_UID" wordpress \
		sh -c "chown -R \${HOST_UID}:33 /var/www/html/wp-content && chmod -R g+rwX /var/www/html/wp-content && find /var/www/html/wp-content -type d -exec chmod g+s {} \;"
else
	echo "[3/5] wp-content.tar.gz assente, skip."
fi

echo "[4/5] Import database..."
docker compose exec -T db mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`; CREATE DATABASE \`${MYSQL_DATABASE}\`;"
docker compose exec -T db mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < "${RESTORE_DIR}/db.sql"

echo "[5/5] Avvio WordPress e search-replace URL..."
docker compose up -d wordpress
sleep 5

if [[ -n "$OLD_URL" && -n "$NEW_URL" ]]; then
	if docker compose --profile tools run --rm \
		-e WORDPRESS_DB_HOST=db \
		-e WORDPRESS_DB_USER="${MYSQL_USER}" \
		-e WORDPRESS_DB_PASSWORD="${MYSQL_PASSWORD}" \
		-e WORDPRESS_DB_NAME="${MYSQL_DATABASE}" \
		wpcli search-replace "$OLD_URL" "$NEW_URL" --all-tables --allow-root 2>/dev/null; then
		:
	else
		echo "      Search-replace non eseguito. Aggiorna siteurl/home in Impostazioni > Generali."
	fi
fi

echo ""
echo "=============================================="
echo "  Restore completato."
echo "=============================================="
echo ""
echo "Sito: http://localhost:${WORDPRESS_PORT:-8080}"
echo ""
