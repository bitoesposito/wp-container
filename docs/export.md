## export.sh

Script to create a full backup of the WordPress installation running via Docker Compose.

### What it does

- Checks that the `.env` file exists and loads `MYSQL_DATABASE` and `MYSQL_ROOT_PASSWORD`.
- Verifies that the `wordpress` container is running.
- Creates a new folder inside `backup/` with a timestamp (`YYYY-MM-DD_HH-MM-SS`).
- Performs:
  - a MariaDB database dump (`db.sql`);
  - a compressed archive of `wordpress/wp-content` (`wp-content.tar.gz`);
  - a copy of the current `docker-compose.yml`;
  - a `manifest.txt` file with backup metadata (database and site URL).

### Prerequisites

- Docker and Docker Compose installed.
- `.env` file present in the project root (copied from `.env.example`).
- Stack started at least once with:

```bash
docker compose up -d
```

### How to run it

```bash
./export.sh
```

The script:

- uses credentials from `.env`;
- saves the database dump using `mariadb-dump` on the `db` service;
- compresses `wordpress/wp-content` if it exists;
- tries to read the site URL via:

```bash
docker compose exec -T wordpress wp option get siteurl --allow-root
```

and writes it into `manifest.txt` as `SITE_URL=...`.

### Backup output

In `backup/<timestamp>/` you will find:

- `db.sql`  
  Full dump of the `MYSQL_DATABASE` database.

- `wp-content.tar.gz`  
  Archive with themes, plugins and uploads (if the `wordpress/wp-content` folder exists).

- `docker-compose.yml`  
  Copy of the configuration file used at export time.

- `manifest.txt`  
  Backup metadata: date, path, contents, database name and, if detected, `SITE_URL`.

