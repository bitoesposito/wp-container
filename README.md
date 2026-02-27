# WordPress Docker Workspace

Minimal environment to run WordPress with MariaDB using Docker Compose, with backup and restore scripts.

## Contents

```bash
.
├── docker-compose.yml    # Services: db (MariaDB) and wordpress
├── .env.example          # Example configuration (.env to copy and modify)
├── export.sh             # Guided export of database + wp-content
├── restore.sh            # Guided restore from backup
└── backup/               # Created by the scripts, contains backups
```

## Quick usage

1. Copy `.env.example` to `.env` and adjust the variables (especially passwords and `WORDPRESS_PORT`).
2. Start the stack:
   ```bash
   docker compose up -d
   ```
3. Access WordPress at `http://localhost:<WORDPRESS_PORT>` (default `8080`).

### Backup

```bash
./export.sh
```

Creates a directory in `backup/` with:
- `db.sql` (MariaDB dump)
- `wp-content.tar.gz` (themes, plugins, uploads)
- `manifest.txt` (backup metadata)

### Restore

```bash
./restore.sh
```

Lets you choose a backup, restores the database and `wp-content` and, if requested, updates URLs via `wp-cli`.

