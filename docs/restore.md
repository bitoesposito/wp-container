## restore.sh

Interactive script to restore a backup created with `export.sh` on a WordPress/MariaDB stack started via Docker Compose.

### What it does

- Lists valid subfolders in `backup/` (those containing `db.sql`).
- Asks which backup to restore.
- Handles database credentials using `.env` and validates required variables.
- Reads any `SITE_URL` from the backup `manifest.txt`.
- Computes a default URL for the new site (`http://localhost:<WORDPRESS_PORT>`).
- Starts the required containers, restores files and database and, if requested, runs a URL `search-replace`.

### Prerequisites

- `backup/` folder with at least one backup created by `export.sh`.
- Docker and Docker Compose installed.
- Compatible `docker-compose.yml` present in the project root.
- Recommended: `.env` file with the same credentials used by the stack.

### Operational flow

1. **Backup selection**
   - The script lists available backups, for example:
     - `backup/2025-01-01_12-00-00`
     - `backup/2025-02-10_09-30-15`
   - Enter the number corresponding to the backup you want to restore.

2. **DB credentials**
   - The script loads credentials from `.env` and ensures:
     - `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD` are all set.
   - If any are missing, it exits with an explicit message asking to fix `.env` before proceeding.

3. **Old and new URLs**
   - If `SITE_URL=...` is present in the backup `manifest.txt`, it is proposed as the old URL.
   - If not, you can manually enter an old URL or leave it empty to skip the URL replacement.
   - A default new URL is computed as:

   ```bash
   http://localhost:${WORDPRESS_PORT:-8080}
   ```

   - If you specify an old URL, you are asked to confirm/override the new URL.

4. **Restoring services and data**
   - Starts the `db` service (and `wordpress` if possible).
   - Temporarily stops `wordpress` to restore files.
   - If `wp-content.tar.gz` exists in the backup:
     - mounts the backup into the container;
     - replaces `/var/www/html/wp-content` with the archive contents;
     - fixes ownership and permissions for the host user.
   - For the database:
     - runs `DROP DATABASE IF EXISTS` and `CREATE DATABASE` for `MYSQL_DATABASE`;
     - imports `db.sql` using `mariadb` inside the `db` container.

5. **URL search-replace (optional)**
   - If both old and new URLs are provided:
     - uses the `tools` profile and the `wpcli` service to run:

     ```bash
     wp search-replace OLD_URL NEW_URL --all-tables --allow-root
     ```

   - If the command fails, the script prints a note that `siteurl` and `home`
     must be updated manually from Settings > General in WordPress.

6. **Conclusion**
   - Restarts `wordpress`.
   - Shows the final expected URL:

   ```bash
   http://localhost:${WORDPRESS_PORT:-8080}
   ```

### How to run

To start the restore:

```bash
./restore.sh
```

Follow the on-screen instructions to:

- select the backup;
- confirm/provide DB credentials in `.env`;
- choose whether to update the site URLs or not.

