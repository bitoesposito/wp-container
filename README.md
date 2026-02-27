# WordPress Docker Workspace

Minimal environment to run WordPress 6.9.1 with MariaDB using Docker Compose, with backup and restore scripts.

## Contents

```bash
.
├── docker-compose.yml    # Services: db (MariaDB) and wordpress
├── .env.example          # Example configuration (.env to copy and modify)
├── scripts/              # Helper scripts (export, restore, wp-cli wrapper)
└── backup/               # Created by the scripts, contains backups
```

## Quick usage

1. Copy `.env.example` to `.env` and adjust the variables (especially passwords and `WORDPRESS_PORT`).
2. (Optional but recommended) set a project name so multiple projects can coexist cleanly on the same host:
   ```bash
   export COMPOSE_PROJECT_NAME=my-wordpress-6-9-1
   ```

3. Start the stack:
   ```bash
   docker compose up -d
   ```
4. Access WordPress at `http://localhost:<WORDPRESS_PORT>` (default `8080`).

### WP-CLI (helper script)

To run `wp-cli` against this stack without typing the full Docker command, use the provided helper:

```bash
./scripts/wp.sh plugin list
```

The script:

- ensures `db` and `wordpress` services are running (starting them if needed);
- invokes the `wpcli` service with the `tools` profile;
- passes all arguments you provide directly to `wp`.

### Backup

```bash
./scripts/export.sh
```

Creates a directory in `backup/` with:
- `db.sql` (MariaDB dump)
- `wp-content.tar.gz` (themes, plugins, uploads)
- `manifest.txt` (backup metadata)

### Restore

```bash
./scripts/restore.sh
```

Lets you choose a backup, restores the database and `wp-content` and, if requested, updates URLs via `wp-cli`.

