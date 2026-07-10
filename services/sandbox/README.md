# Sandbox

Self-hosted AI frontend (LibreChat) plus its MongoDB backup job (rclone).
Grouped together because neither has a shared dependency with anything else
in the stack — LibreChat runs on Nat's node (`nat-server`), accessible over
Tailscale only, not exposed to the public internet. rclone runs as an
ephemeral container invoked by cron, not a long-running service.

## Stack

| Component | Image | Purpose |
|-----------|-------|---------|
| LibreChat | `yvchenko/librechat-custom-tagging:latest` | AI frontend |
| MongoDB | `mongo:8.0.20` | Conversation and user data |
| MeiliSearch | `getmeili/meilisearch:v1.35.1` | Conversation search index |
| pgvector | `pgvector/pgvector:0.8.0-pg15-trixie` | Vector store for RAG |
| RAG API | `librechat-rag-api-dev-lite:latest` | Retrieval-augmented generation |
| rclone | `rclone/rclone:latest` | MongoDB → Google Drive backup (cron-invoked) |

## Why a custom LibreChat image?

Two patches are applied on top of the upstream build:

**Bookmark AND filtering** — upstream uses `$in` (OR) when filtering
conversations by multiple tags. Changed to `$all` (AND) so selecting multiple
bookmarks returns only conversations that have all of them. Patch lives in
`packages/data-schemas/dist/methods/conversation.cjs` and `conversation.es.js`.

**Frontend defaults** — `enterToSend` and `autoScroll` defaulted to `false`.
The compiled client bundle reflecting these changes is copied in at image
build time.

Image published to Docker Hub as `yvchenko/librechat-custom-tagging:latest`.

## Paths

| Purpose          | Host path                                | Container path              |
|------------------|-------------------------------------------|-----------------------------|
| Config           | `services/sandbox/librechat/.env`          | `/app/.env`                 |
| LibreChat config | `services/sandbox/librechat/librechat.yaml`| `/app/librechat.yaml`       |
| Images           | `/opt/appdata/librechat/images`            | `/app/client/public/images` |
| Uploads          | `/opt/appdata/librechat/uploads`           | `/app/uploads`              |
| Logs             | `/opt/appdata/librechat/logs`              | `/app/logs`                 |
| MongoDB data     | `/opt/appdata/librechat/db`                | `/data/db`                  |
| MeiliSearch data | `/opt/appdata/librechat/meili_data`        | `/meili_data`               |
| pgvector data    | `/opt/appdata/librechat/pgdata`            | `/var/lib/postgresql/data`  |
| rclone config    | `/opt/rclone/rclone.conf`                  | `/config/rclone/rclone.conf` (ro) |
| Backup archives  | `/opt/backups/`                            | `/data` (ro)                |
| Backup log       | `/var/log/mongo_backup.log`                | —                            |

## First run

```bash
# Create LibreChat directories
sudo mkdir -p /opt/appdata/librechat/{images,uploads,logs,db,meili_data,pgdata}

# Copy and fill in config files
cd services/sandbox/librechat
cp .env.example .env
# edit .env with your values
cd ../..

# Start the stack
docker compose up -d

# Logs
docker compose logs -f
```

The first user to register in LibreChat becomes the admin.

## Configuration

**`librechat.yaml`** — primary config. Controls enabled endpoints, interface
features, and model definitions. See the [LibreChat docs](https://docs.librechat.ai)
for the full schema.

**`.env`** — secrets and environment variables. Never commit this file. See
`.env.example` for required keys.

### User-provided API keys

Custom endpoints can be set to `apiKey: "user_provided"` so each user supplies
their own key via the UI instead of using a shared key from `.env`.

**`CREDS_KEY` and `CREDS_IV` must be set in `.env`** — these encrypt
user-provided keys before they're stored in MongoDB. Without real values, keys
appear to save successfully in the UI but fail silently on lookup
(`no_user_key` errors). Generate with:

```bash
openssl rand -hex 32   # CREDS_KEY
openssl rand -hex 16   # CREDS_IV
```

Changing these after keys already exist invalidates all stored keys/sessions
— only regenerate once, not casually.

## Backup (rclone)

Backs up MongoDB (LibreChat) to Google Drive. Daily at 03:00 UTC via root
crontab, using `tools/scripts/backup_mongo.sh`. Remote: `nat:homelab-backups/nat-server`.

### One-time setup

**1. Create config dir**

```bash
sudo mkdir -p /opt/rclone
```

**2. Authorize Google Drive**

Run on a machine with Docker **and a browser** (e.g. your laptop):

```bash
docker run --rm -it -p 53682:53682 rclone/rclone authorize "drive" "token"
```

> ⚠️ The `-p 53682:53682` flag is required — without it the callback port
> isn't reachable from the browser. rclone prints a URL; open it, authorize
> with Google, paste the resulting token back.

Then on nat-server, run the interactive config:

```bash
sudo docker run --rm -it -v /opt/rclone:/config/rclone rclone/rclone config
```

- New remote → name it `nat` → type `drive`
- Leave client_id and client_secret blank
- Scope: `1` (full access)
- Auto config: `n` (headless) → paste the token from the previous step

> ⚠️ Do not use `-v /opt/rclone/rclone.conf:/config/rclone/rclone.conf` here
> — if the file doesn't exist yet Docker will create it as a directory. Mount
> the parent dir instead.

Verify:

```bash
sudo docker run --rm -v /opt/rclone:/config/rclone rclone/rclone listremotes
# expected: nat:
```

**3. Create backup dirs**

```bash
sudo mkdir -p /opt/backups
sudo touch /var/log/mongo_backup.log
```

**4. Pull the repo and set up cron**

```bash
cd ~/homelab && git pull
sudo crontab -e
```

Add:
```
0 3 * * * /home/nat/homelab/tools/scripts/backup_mongo.sh
```

### Testing

Set cron to 2 minutes from now, then watch the log:

```bash
tail -f /var/log/mongo_backup.log
```

After confirming it works, reset to `0 3 * * *`.

## Updating the LibreChat image

The custom image is pinned to a specific upstream state and is not updated
automatically. To update:

1. Merge upstream `main` into the local branch
2. Rebuild the client: `npx turbo run build --filter=@librechat/frontend --force`
3. Re-extract and re-patch `packages/data-schemas/dist/methods/conversation.cjs`
   and `conversation.es.js` (change `$in` back to `$all` in `getConvosByCursor`)
4. Rebuild and push: `docker compose build && docker push yvchenko/librechat-custom-tagging:latest`
5. On the server: `docker compose pull && docker compose up -d`

## Known gotchas

- MongoDB at `/opt/appdata/librechat/db` is the critical backup target — it
  holds all conversations and user data. MeiliSearch is a search index and
  rebuilds itself from MongoDB on startup, so it doesn't need backing up.
- `backup_mongo.sh` must have the executable bit set in git
  (`git update-index --chmod=+x`), not just on disk — cron runs it directly,
  not via `bash`.
- The backup script uses `docker compose run` (not `docker run`), so the
  compose file must be present at `~/homelab/services/sandbox/docker-compose.yml`.
  This path changed with the sandbox merge — double-check `backup_mongo.sh`
  points here and not at the old `services/rclone/docker-compose.yml`.
- Remote cleanup deletes archives older than 30 days from GDrive. Local
  retention is 5 days.
- MongoDB container is expected to be named `chat-mongodb`. Update
  `MONGO_CONTAINER` in the script if it changes.