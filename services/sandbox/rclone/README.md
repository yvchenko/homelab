# rclone

Backs up MongoDB (LibreChat) to Google Drive via rclone. Runs as an ephemeral container invoked by a cron job — not a long-running service.

## Stack

| Component | Details |
|---|---|
| Image | `rclone/rclone:latest` |
| Backup script | `tools/scripts/backup_mongo.sh` |
| Schedule | Daily at 03:00 UTC (root crontab) |
| Remote | `nat:homelab-backups/nat-server` |

## Paths

| Path | Description |
|---|---|
| `/opt/rclone/rclone.conf` | rclone config with GDrive OAuth token — **not in git** |
| `/opt/backups/` | Local backup archives (5-day retention) |
| `/var/log/mongo_backup.log` | Backup log |

## One-time setup

### 1. Create config dir

```bash
sudo mkdir -p /opt/rclone
```

### 2. Authorize Google Drive

Run this on a machine that has Docker **and a browser** (e.g. your laptop):

```bash
docker run --rm -it -p 53682:53682 rclone/rclone authorize "drive" "token"
```

> ⚠️ The `-p 53682:53682` flag is required — without it the callback port isn't reachable from the browser.
> rclone will print a URL. Open it, authorize with Google, then paste the resulting token back.

Then on nat-server, run the interactive config:

```bash
sudo docker run --rm -it -v /opt/rclone:/config/rclone rclone/rclone config
```

- New remote → name it `nat` → type `drive`
- Leave client_id and client_secret blank
- Scope: `1` (full access)
- Auto config: `n` (headless) → paste the token from the previous step

> ⚠️ Do not use `-v /opt/rclone/rclone.conf:/config/rclone/rclone.conf` here — if the file doesn't exist yet Docker will create it as a directory. Mount the parent dir instead.

Verify:

```bash
sudo docker run --rm -v /opt/rclone:/config/rclone rclone/rclone listremotes
# expected: nat:
```

### 3. Create backup dirs

```bash
sudo mkdir -p /opt/backups
sudo touch /var/log/mongo_backup.log
```

### 4. Pull the repo and set up cron

```bash
cd ~/homelab && git pull
sudo crontab -e
```

Add:

```
0 3 * * * /home/nat/homelab/tools/scripts/backup_mongo.sh
```

## Testing

Set cron to 2 minutes from now, then watch the log:

```bash
tail -f /var/log/mongo_backup.log
```

After confirming it works, reset to `0 3 * * *`.

## Caveats

- `rclone.conf` contains OAuth tokens — never commit it. It's gitignored.
- `backup_mongo.sh` must have the executable bit set in git (`git update-index --chmod=+x`), not just on disk — cron runs it directly, not via `bash`.
- The backup script uses `docker compose run` (not `docker run`) so the compose file must be present at `~/homelab/services/rclone/docker-compose.yml`.
- Remote cleanup deletes archives older than 30 days from GDrive. Local retention is 5 days.
- MongoDB container is expected to be named `chat-mongodb`. Update `MONGO_CONTAINER` in the script if it changes.