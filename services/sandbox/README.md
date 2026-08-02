# Sandbox

Self-hosted AI frontend (LibreChat) plus its MongoDB backup job. Single-node
cluster — everything runs on Nat's node (`nat-server`), accessible over
Tailscale only, not exposed to the public internet.

## Stack

| Component | Image | Purpose |
|-----------|-------|---------|
| LibreChat (`librechat`) | `yvchenko/librechat-custom-tagging:latest` | AI frontend |
| MongoDB (`mongodb`) | `mongo:8.0.x` (see pinned-version gotcha below — `8.0.20` specifically is known-bad) | Conversation and user data |
| MeiliSearch (`meilisearch`) | `getmeili/meilisearch:v1.35.1` | Conversation search index |
| vectordb (`vectordb`) | `pgvector/pgvector:0.8.0-pg15-trixie` | Vector store for RAG |
| RAG API (`rag-api`) | `registry.librechat.ai/danny-avila/librechat-rag-api-dev-lite:latest` | Retrieval-augmented generation |

All five run as k8s Deployments in the `sandbox` namespace. `mongodb`,
`meilisearch`, `vectordb`, and `rag-api` each have a plain `ClusterIP`
Service, so container-name-style DNS (`mongodb:27017`,
`http://rag-api:8000`, etc.) works exactly like Compose's bridge-network
resolution — no `hostNetwork`, no DNS gotchas here, unlike most of the rest
of this migration. Only `librechat` itself is externally reachable, via
`hostPort: 3080`.

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
| Images           | `/opt/appdata/librechat/images`            | `/app/client/public/images` |
| Uploads          | `/opt/appdata/librechat/uploads`           | `/app/uploads`              |
| Logs             | `/opt/appdata/librechat/logs`              | `/app/logs`                 |
| MongoDB data     | `/opt/appdata/librechat/db`                | `/data/db`                  |
| MeiliSearch data | `/opt/appdata/librechat/meili_data`        | `/meili_data`               |
| pgvector data    | `/opt/appdata/librechat/pgdata`            | `/var/lib/postgresql/data`  |
| rclone config    | `/opt/rclone/rclone.conf`                  | `/config/rclone/rclone.conf` (mounted directly — no `subPath`, see gotcha below) |
| Backup archives  | `/opt/backups/`                            | `/backups`                  |

All mounted via `hostPath`. **`librechat.yaml` is a ConfigMap, not a
bind-mounted file** — see Configuration below. There is **no `.env` file
mounted at all** — every value that used to live there is now a real
container env var (see Configuration).

## First run

```bash
sudo mkdir -p /opt/appdata/librechat/{images,uploads,logs,db,meili_data,pgdata}

sudo k3s kubectl create namespace sandbox

# ...create Secrets and ConfigMaps (see Configuration below)...

sudo k3s kubectl apply -f services/sandbox/mongodb/manifest.yaml
sudo k3s kubectl apply -f services/sandbox/meilisearch/manifest.yaml
sudo k3s kubectl apply -f services/sandbox/vectordb/manifest.yaml
sudo k3s kubectl apply -f services/sandbox/rag_api/manifest.yaml
sudo k3s kubectl apply -f services/sandbox/librechat/manifest.yaml
sudo k3s kubectl get pods -n sandbox -o wide

# Logs
sudo k3s kubectl logs -n sandbox <pod-name> -f
```

The first user to register in LibreChat becomes the admin.

## Configuration

**No `.env` file is mounted into the container anymore.** dotenv (the
library LibreChat uses) doesn't override values already present in
`process.env`, so every value — secret and non-secret alike — is injected
directly as a real container env var instead: `envFrom: configMapRef` for
everything non-sensitive, `envFrom: secretRef` for everything sensitive.
This avoids the k8s-side problem of trying to merge a Secret and a
ConfigMap into one physical file.

**Non-secret config** — `librechat-env` ConfigMap, generated from a real
committed file (`services/sandbox/librechat/librechat.env`) via
`--from-env-file`, which correctly skips comment lines and blanks the same
way any `.env` parser does:

```bash
sudo k3s kubectl create configmap librechat-env \
  --namespace sandbox \
  --from-env-file=services/sandbox/librechat/librechat.env
```

**`librechat.yaml`** — still the primary endpoint/interface/model config
file, but now loaded as a ConfigMap from the same committed source file and
mounted from there, rather than bind-mounted directly:

```bash
sudo k3s kubectl create configmap librechat-config \
  --namespace sandbox \
  --from-file=librechat.yaml=services/sandbox/librechat/librechat.yaml
```

See the [LibreChat docs](https://docs.librechat.ai) for the full schema.

**Secrets** — `librechat-secrets`, created imperatively, never committed:

```bash
sudo k3s kubectl create secret generic librechat-secrets \
  --namespace sandbox \
  --from-literal=MEILI_MASTER_KEY='...' \
  --from-literal=CREDS_KEY='...' \
  --from-literal=CREDS_IV='...' \
  --from-literal=JWT_SECRET='...' \
  --from-literal=JWT_REFRESH_SECRET='...'
```

`vectordb`'s Postgres credentials — previously hardcoded plaintext directly
in the compose file — also became a Secret as part of this migration
(retrofitted, not translated from an existing `.env` value):

```bash
sudo k3s kubectl create secret generic vectordb-secrets \
  --namespace sandbox \
  --from-literal=POSTGRES_DB='mydatabase' \
  --from-literal=POSTGRES_USER='myuser' \
  --from-literal=POSTGRES_PASSWORD='...'
```

### User-provided API keys

Custom endpoints can be set to `apiKey: "user_provided"` so each user supplies
their own key via the UI instead of using a shared key.

**`CREDS_KEY` and `CREDS_IV` must be set in the `librechat-secrets` Secret**
— these encrypt user-provided keys before they're stored in MongoDB.
Without real values, keys appear to save successfully in the UI but fail
silently on lookup (`no_user_key` errors). Generate with:

```bash
openssl rand -hex 32   # CREDS_KEY
openssl rand -hex 16   # CREDS_IV
```

Changing these after keys already exist invalidates all stored keys/sessions
— only regenerate once, not casually.

## Backup (CronJob)

Backs up MongoDB to Google Drive. Runs as a k8s **CronJob**
(`services/sandbox/backup/manifest.yaml`), not a system crontab entry —
schedule is set in the manifest itself (`schedule: "0 3 * * *"`, matching
the original daily 03:00 timing). Remote: `nat:homelab-backups/nat-server`.

The actual dump/upload/cleanup logic is committed as two real shell scripts
(`mongo-backup.sh`, `rclone-sync.sh`) rather than embedded inline in the
CronJob YAML, loaded via a ConfigMap:

```bash
sudo k3s kubectl create configmap mongo-backup-scripts \
  --namespace sandbox \
  --from-file=mongo-backup.sh=services/sandbox/backup/mongo-backup.sh \
  --from-file=rclone-sync.sh=services/sandbox/backup/rclone-sync.sh
```

**`mongodump` now runs over the network**, not via `docker exec` into a
live container — the old script's `docker exec chat-mongodb mongodump`
approach doesn't translate directly to k8s (exec-ing into a sibling pod
isn't the idiomatic pattern here). Instead, an `initContainer` in the
CronJob runs `mongodump --host mongodb --port 27017 ...` against the
`mongodb` Service's ClusterIP DNS name, same as any other client of that
Service.

### One-time setup

**1. Create config dir**

```bash
sudo mkdir -p /opt/rclone
```

**2. Authorize Google Drive**

Run on a machine with Docker **and a browser** (e.g. your laptop) — this
one-time interactive step still uses plain `docker run`, since it needs a
local browser round-trip and isn't something the cluster itself should do:

```bash
docker run --rm -it -p 53682:53682 rclone/rclone authorize "drive" "token"
```

> ⚠️ The `-p 53682:53682` flag is required — without it the callback port
> isn't reachable from the browser. rclone prints a URL; open it, authorize
> with Google, paste the resulting token back.

Then on nat-server, run the interactive config (still plain `docker run`,
same one-time-setup reasoning):

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

**3. Create backup dir and apply the CronJob**

```bash
sudo mkdir -p /opt/backups

sudo k3s kubectl apply -f services/sandbox/backup/manifest.yaml
```

### Testing

Trigger a manual run any time, outside the schedule:

```bash
sudo k3s kubectl create job --from=cronjob/mongo-backup mongo-backup-test -n sandbox
sudo k3s kubectl get pods -n sandbox -o wide | grep mongo-backup-test
```

Once it completes, **check the actual archive file, don't just trust a
`Completed` status** — a Job can complete cleanly with clean logs while
still producing an empty archive if something upstream (e.g. `mongodump`
itself) silently failed:

```bash
ls -la /opt/backups/
```

Confirm a real, non-zero-byte `mongo_<timestamp>.gz` exists before trusting
the pipeline. Clean up the test job afterward:

```bash
sudo k3s kubectl delete job mongo-backup-test -n sandbox
```

## Updating the LibreChat image

1. Merge upstream `main` into the local branch
2. Rebuild the client: `npx turbo run build --filter=@librechat/frontend --force`
3. Re-extract and re-patch `packages/data-schemas/dist/methods/conversation.cjs`
   and `conversation.es.js` (change `$in` back to `$all` in `getConvosByCursor`)
4. Rebuild and push: `docker build -t yvchenko/librechat-custom-tagging:latest . && docker push yvchenko/librechat-custom-tagging:latest`
5. On the server, force a fresh pull and rollout:
   ```bash
   sudo k3s kubectl delete pod -n sandbox -l app=librechat
   ```
   (the Deployment recreates it automatically, pulling the new `:latest` tag)

## Known gotchas

- **MongoDB only listens on loopback by default — it will not accept
  connections from any other pod until told otherwise.** A fresh mongodb
  pod can look completely healthy (`Running`, no errors) while LibreChat
  fails with `connect ECONNREFUSED <mongodb-ClusterIP>:27017`. Confirmed by
  mongod's own log: `"This server is bound to localhost"` /
  `"Listening on","address":"127.0.0.1:27017"`. **Fix: `command: ["mongod",
  "--noauth", "--bind_ip_all"]`** in the manifest — this is a MongoDB
  default, not anything Compose was doing differently; it just never
  mattered under Compose because of how that setup reached it.

- **A real MongoDB build can segfault (exit code 139) with a completely
  clean, uncorrupted database.** Hit a `CrashLoopBackOff` on `mongo:8.0.20`
  specifically, crashing every time immediately after LibreChat's driver
  connected. `mongod --repair` (run via a one-off pod against the same real
  data directory, Deployment scaled to 0 first to release the file lock)
  came back completely clean — zero corrupt documents across every
  collection — and the crash still recurred identically on a freshly
  repaired, verified-clean database. Ruled out memory exhaustion too
  (`free -h` showed plenty available, no OOM entries in `dmesg`). **A
  clean repair + no OOM evidence + no fatal assertion in the log (expected
  for a genuine SIGSEGV — the kernel kills the process before it can log
  its own death) is a strong signal to stop debugging config/data and just
  try a different image tag.** Pinning to a different 8.0.x build resolved
  it — fill in the exact tag you land on once confirmed stable over time,
  and treat it as **do not casually bump this specific image without
  testing first**, since `8.0.20` looking fine at build/pull time didn't
  predict this bug.

- **`subPath` breaks when the underlying `hostPath` is already a single
  file, not a directory.** The rclone config mount originally used
  `subPath: rclone.conf` (copied from a pattern that made sense for a
  directory-based ConfigMap volume) — but `/opt/rclone/rclone.conf` is
  already the exact file, so `subPath` had nothing to look "inside," and
  the mount failed outright (`failed to prepare subPath for volumeMount`).
  Fixed by dropping `subPath` entirely and mounting the hostPath file
  directly at the target path.

- MongoDB at `/opt/appdata/librechat/db` is the critical backup target — it
  holds all conversations and user data. MeiliSearch is a search index and
  rebuilds itself from MongoDB on startup, so it doesn't need backing up.
- Remote cleanup deletes archives older than 30 days from GDrive. Local
  retention is 5 days.
