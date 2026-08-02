# Reading Library

Manga, manhwa, ebook, and comic library stack. Runs on `kostyan-server`.
Accessible over Tailscale only — not exposed to the public internet.

Suwayomi downloads chapters from web sources; Kavita serves the resulting
library for reading. They don't talk to each other directly — a scheduled
job bridges the two by flattening Suwayomi's download structure into the
layout Kavita (and eventually Komga) expects as a library.

## Stack

| Component | Image | Purpose |
|---|---|---|
| Kavita | `lscr.io/linuxserver/kavita:0.8.9` | Manga/ebook/comic reader and library server |
| Suwayomi | `ghcr.io/suwayomi/suwayomi-server:stable` | Manga/manhwa downloader (Tachiyomi/Mihon extension ecosystem) |

Both run as k8s Deployments in the `reading-library` namespace, single
instance each, pinned to `kostyan-server` (`nodeSelector: disk: kostyan-media`).

**Kavita image note**: switched from `jvmilazz0/kavita` to
`lscr.io/linuxserver/kavita` for more active maintenance/security patching.
This is a lateral move, not a version bump — linuxserver's stable tag
(`0.8.9`) is actually a touch older than the previous `0.9.0`. Config data
carried over untouched; only the **container-side mount path changed**,
from `/kavita/config` to `/config` (see Paths below) — the linuxserver wiki
explicitly documents this as the migration step from the official image.

## Paths

| Purpose | Host path | Container path |
|---|---|---|
| Kavita config & database | `/opt/appdata/kavita` | `/config` (was `/kavita/config` under the old image) |
| Books | `/mnt/media/books` | `/media/books` |
| Manga (Kavita-facing) | `/mnt/media/manga` | `/media/manga` |
| Danmei | `/mnt/media/danmei` | `/media/danmei` |
| Ranobe | `/mnt/media/ranobe` | `/media/ranobe` |
| Comics | `/mnt/media/comics` | `/media/comics` |
| Suwayomi downloads | `/mnt/media/suwayomi` | `/home/suwayomi/.local/share/Tachidesk/downloads` |
| Suwayomi config/db/extensions | `/opt/appdata/suwayomi` | `/home/suwayomi/.local/share/Tachidesk` |

All mounted via `hostPath` in each Deployment's manifest. The old
"must-be-first-volume-entry" ordering requirement from Compose doesn't
apply to k8s volume lists — order is irrelevant here.

Suwayomi downloads land at `/mnt/media/suwayomi/mangas/<Source Name>/<Manga Title>/<chapter folder>`.

## Post-download library sync

Suwayomi and Kavita expect different folder structures, so downloads are
staged separately and flattened by a script rather than downloaded directly
into the library:

| Path | Purpose |
|---|---|
| `/mnt/media/suwayomi/mangas/<source-site>/<series-name>/` | Suwayomi's download structure (staging area, not a library) |
| `/mnt/media/manga/<series-name>/` | Flat per-series structure Kavita scans as a library |

**Script**: `services/reading-library/suwayomi-move.sh`

- Merges all source-site variants of a series into one destination folder
  (e.g. a series downloaded from both Mangadex and Asura Scans lands in a
  single `/mnt/media/manga/<series-name>/` folder)
- Files are **moved**, not copied — Suwayomi's originals are not preserved
- Cleans up empty source-site folders under `/mnt/media/suwayomi/mangas/`
  after each run
- Config (`SRC`, `DEST`, `LOG`) is set at the top of the script

Runs as a k8s **CronJob**, not a system cron entry. The script itself is
committed as a real file in the repo and loaded into the job via a
`ConfigMap` (`--from-file`), rather than being duplicated inline in the
CronJob YAML — same "config lives as a real file, not inline" convention
used everywhere else in this migration:

```bash
sudo k3s kubectl create configmap suwayomi-move-script \
  --namespace reading-library \
  --from-file=suwayomi-move.sh=services/reading-library/suwayomi-move.sh

sudo k3s kubectl apply -f services/reading-library/suwayomi-move/manifest.yaml
```

Schedule is set in the manifest itself (`schedule: "0 4 * * *"`, matching
the original daily 04:00 timing), not in a separate crontab.

```bash
# manual run, outside the schedule
sudo k3s kubectl create job --from=cronjob/suwayomi-move suwayomi-move-manual -n reading-library
sudo k3s kubectl get pods -n reading-library -o wide | grep suwayomi-move
```

## Networking

Suwayomi runs with `hostNetwork: true` and reaches FlareSolverr via
`http://localhost:8191` — FlareSolverr's own pod (part of `media-download/`'s
arr-stack DaemonSet) already runs on kostyan-server with `hostNetwork: true`
too, so both share the same real network namespace and `localhost` genuinely
resolves to the same host. **No cross-namespace Service reference needed,
and no startup-order dependency on `media-download/` being up first** — this
replaces the old Compose setup's external `media_download` network
attachment entirely.

Suwayomi's `hostNetwork` pod also carries the same `dnsPolicy: None` +
explicit `dnsConfig` fix used across every `hostNetwork` workload in this
cluster (Tailscale's resolver + a public fallback) — needed since Suwayomi
fetches from real manga/manhwa sites over the internet.

Kavita has no network dependency on anything else and doesn't use
`hostNetwork` — just a plain `hostPort: 5000` to keep it reachable at the
same address as before.

## First run

### Kavita config

```bash
sudo mkdir -p /opt/appdata/kavita
```

### Suwayomi

World-writable required, do NOT `chown 1000:1000` here.
Suwayomi's image expects arbitrary container UIDs to write to its data dirs.
This applies to Suwayomi's own appdata/downloads mount only — `/mnt/media/manga`,
the Kavita-facing output of the move script, keeps standard `grim:grim` ownership.

```bash
mkdir -p /mnt/media/suwayomi && chmod -R 777 /mnt/media/suwayomi
```

### Start

```bash
sudo k3s kubectl create namespace reading-library
sudo k3s kubectl apply -f services/reading-library/kavita/manifest.yaml
sudo k3s kubectl apply -f services/reading-library/suwayomi/manifest.yaml
sudo k3s kubectl apply -f services/reading-library/suwayomi-move/manifest.yaml
sudo k3s kubectl get pods -n reading-library -o wide
```

### Logs

```bash
sudo k3s kubectl logs -n reading-library <pod-name> -f
```

## Post-setup — required

### Kavita:
1. The first user to register becomes the admin.
2. Add `/media/manga`, `/media/books`, etc. as libraries in the UI after logging in.

### Suwayomi:
1. Open the web UI → **Browse → Extension → Settings → Extension repositories**
2. Add repo using the **raw JSON URL**, not the GitHub landing page:

```
https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json
```

(the shorthand `https://github.com/keiyoushi/extensions` form throws a
   `ProtobufDecodingException` on the current Extension Store system)
3. Restart the pod after adding the repo to force a clean fetch:
   ```bash
   sudo k3s kubectl delete pod -n reading-library <suwayomi-pod-name>
   ```
   (it's a Deployment, so a fresh pod is scheduled automatically)
4. Install extensions: **Mangadex**, **Mangapill** (general), **Asura Scans**,
  **Webtoons** (manhwa)

5. **Settings → Downloads → enable "Save as CBZ"** in Suwayomi. Without this,
  chapters download as loose image folders with no reliable per-chapter
  archive — enabling it makes Suwayomi package each chapter as a proper
  `.cbz` with embedded `ComicInfo.xml`, which Kavita expects for clean
  per-file metadata and portability.
6. Confirm FlareSolverr is reachable if a source requires it:
   ```bash
   sudo k3s kubectl logs -n reading-library <suwayomi-pod-name> | grep -i flaresolverr
   ```

## Migrating Kavita from another instance

To carry over user data, reading progress, and bookmarks, copy the config
directory from the source machine before starting the deployment.

```powershell
# On the source machine (Windows)
Compress-Archive -Path C:\homelab\kavita -DestinationPath C:\homelab\kavita-backup.zip
scp C:\homelab\kavita-backup.zip nat@kostyan-server.salmon-halfmoon.ts.net:/home/nat/kavita-backup.zip
```

```bash
# On target server
unzip ~/kavita-backup.zip -d ~/kavita-extract
sudo cp -r ~/kavita-extract/kavita/* /opt/appdata/kavita/

# Then apply the manifest
sudo k3s kubectl apply -f services/reading-library/kavita/manifest.yaml
```

## Known gotchas

- **Kavita image switch, not just a version bump.** `jvmilazz0/kavita` →
  `lscr.io/linuxserver/kavita` changed the container-side config path
  (`/kavita/config` → `/config`) — a mount-point update, not a data
  migration; the actual host directory (`/opt/appdata/kavita`) is unchanged.
  Worth a backup (`cp -r /opt/appdata/kavita /opt/appdata/kavita.backup-pre-lsio`)
  before switching, since it's a genuine image-family change, not a same-image
  tag bump.
- **Suwayomi permissions**: do not `chown 1000:1000` its appdata/downloads
  mount — it needs world-writable dirs (`chmod 777`) for arbitrary container
  UIDs. This is the one path under `/mnt/media` on kostyan-server that
  deliberately doesn't follow the standard `grim:grim` ownership.
- **Series name matching**: `suwayomi-move.sh` merges by exact folder name
  match. Inconsistent naming across scrapers/sources produces separate,
  unmerged series entries in Kavita.
- **Chapter filename collisions**: if two sources for the same series have
  overlapping chapter filenames, `suwayomi-move.sh` overwrites silently on
  merge — no warning, no backup of the overwritten file.
