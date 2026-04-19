# LibreChat

Self-hosted AI frontend running on a custom Docker image with behavioral patches
applied on top of the official upstream build. 
## Access

| Interface | URL |
|-----------|-----|
| Web UI | http://kostyan-server.salmon-halfmoon.ts.net:3080 |

Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image | Purpose |
|-----------|-------|---------|
| LibreChat | `yvchenko/librechat-custom-tagging:latest` | AI frontend |
| MongoDB | `mongo:8.0.20` | Conversation and user data |
| MeiliSearch | `getmeili/meilisearch:v1.35.1` | Conversation search index |
| pgvector | `pgvector/pgvector:0.8.0-pg15-trixie` | Vector store for RAG |
| RAG API | `librechat-rag-api-dev-lite:latest` | Retrieval-augmented generation |

## Why a custom image?

Two patches are applied on top of the upstream build:

**Bookmark AND filtering** — upstream uses `$in` (OR) when filtering
conversations by multiple tags. Changed to `$all` (AND) so selecting multiple
bookmarks returns only conversations that have all of them. Patch lives in
`packages/data-schemas/dist/methods/conversation.cjs` and `conversation.es.js`.

**Frontend defaults** — `enterToSend` and `autoScroll` defaulted to `false`.
The compiled client bundle reflecting these changes is copied in at image build
time.

Image published to Docker Hub as `yvchenko/librechat-custom-tagging:latest`.

## Paths

| Purpose          | Host path                               | Container path              |
|------------------|-----------------------------------------|-----------------------------|
| Config           | `/opt/appdata/librechat/.env`           | `/app/.env`                 |
| LibreChat config | `/opt/appdata/librechat/librechat.yaml` | `/app/librechat.yaml`       |
| Images           | `/opt/appdata/librechat/images`         | `/app/client/public/images` |
| Uploads          | `/opt/appdata/librechat/uploads`        | `/app/uploads`              |
| Logs             | `/opt/appdata/librechat/logs`           | `/app/logs`                 |
| MongoDB data     | `/opt/appdata/librechat/db`             | `/data/db`                  |
| MeiliSearch data | `/opt/appdata/librechat/meili_data`     | `/meili_data`               |
| pgvector data    | `/opt/appdata/librechat/pgdata`         | `/var/lib/postgresql/data`  |

## First run

```bash
# Create directories
sudo mkdir -p /opt/appdata/librechat/{images,uploads,logs,db,meili_data,pgdata}

# Copy and fill in config files
cp .env.example /opt/appdata/librechat/.env
# edit /opt/appdata/librechat/.env with your values
cp librechat.yaml.example /opt/appdata/librechat/librechat.yaml

# Start
docker compose up -d

# Logs
docker compose logs -f
```

The first user to register becomes the admin.

## Configuration

**`librechat.yaml`** — primary config. Controls enabled endpoints, interface
features, and model definitions. See the [LibreChat docs](https://docs.librechat.ai)
for the full schema.

**`.env`** — secrets and environment variables. Never commit this file. See
`.env.example` for required keys.

## Backup

MongoDB at `/opt/appdata/librechat/db` is the critical backup target —
it contains all conversations and user data. MeiliSearch is a search index
and rebuilds itself from MongoDB on startup, so it does not need to be backed up.

## Updating the image

The custom image is pinned to a specific upstream state and is not updated
automatically. To update:

1. Merge upstream `main` into the local branch
2. Rebuild the client: `npx turbo run build --filter=@librechat/frontend --force`
3. Re-extract and re-patch `packages/data-schemas/dist/methods/conversation.cjs`
   and `conversation.es.js` (change `$in` back to `$all` in `getConvosByCursor`)
4. Rebuild and push: `docker compose build && docker push yvchenko/librechat-custom-tagging:latest`
5. On the server: `docker compose pull && docker compose up -d`