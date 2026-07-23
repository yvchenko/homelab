# Reading Library

Manga, manhwa, ebook, and comic library stack. Runs on `kostyan-server`.
Accessible over Tailscale only — not exposed to the public internet.

Suwayomi downloads chapters from web sources; Kavita serves the resulting
library for reading. They don't talk to each other directly — a cron script
bridges the two by flattening Suwayomi's download structure into the layout
Kavita (and eventually Komga) expects as a library.

## Stack

| Component | Image | Purpose |
|---|---|---|
| Kavita | `jvmilazz0/kavita:0.9.0` | Manga/ebook/comic reader and library server |
| Suwayomi | `ghcr.io/suwayomi/suwayomi-server:stable` | Manga/manhwa downloader (Tachiyomi/Mihon extension ecosystem) |

## Paths

| Purpose | Host path | Container path |
|---|---|---|
| Kavita config & database | `/opt/appdata/kavita` | `/kavita/config` |
| Books | `/mnt/media/books` | `/media/books` |
| Manga (Kavita-facing) | `/mnt/media/manga` | `/media/manga` |
| Danmei | `/mnt/media/danmei` | `/media/danmei` |
| Ranobe | `/mnt/media/ranobe` | `/media/ranobe` |
| Comics | `/mnt/media/comics` | `/media/comics` |
| Suwayomi downloads | `/mnt/media/suwayomi` | `/home/suwayomi/.local/share/Tachidesk/downloads` — **must be first volume entry** (Suwayomi requirement) |
| Suwayomi config/db/extensions | `/opt/appdata/suwayomi` | `/home/suwayomi/.local/share/Tachidesk` |

Suwayomi downloads land at `/mnt/media/suwayomi/mangas/<Source Name>/<Manga Title>/<chapter folder>`.

## Post-download library sync

Suwayomi and Kavita expect different folder structures, so downloads are
staged separately and flattened by a script rather than downloaded directly
into the library:

| Path | Purpose |
|---|---|
| `/mnt/media/suwayomi/mangas/<source-site>/<series-name>/` | Suwayomi's download structure (staging area, not a library) |
| `/mnt/media/manga/<series-name>/` | Flat per-series structure Kavita scans as a library |

**Script**: `tools/scripts/suwayomi-move.sh`

- Merges all source-site variants of a series into one destination folder
  (e.g. a series downloaded from both Mangadex and Asura Scans lands in a
  single `/mnt/media/manga/<series-name>/` folder)
- Files are **moved**, not copied — Suwayomi's originals are not preserved
- Cleans up empty source-site folders under `/mnt/media/suwayomi/mangas/`
  after each run
- Config (`SRC`, `DEST`, `LOG`) is set at the top of the script

**Schedule**: daily via cron, plus manual trigger any time:

```
0 4 * * * /home/nat/homelab/tools/scripts/suwayomi-move.sh
```

```bash
# manual run
./tools/scripts/suwayomi-move.sh
```

## Networking

Suwayomi attaches to the `media_download` network (external) to reach
FlareSolverr by container name (`http://flaresolverr:8191`). Kavita has no
network dependency on anything else — nothing currently talks to it by
container name, so it uses the default bridge.

**Startup order matters**: `media-download/` must be up before this stack,
or Suwayomi fails to start with a network-not-found error since
`media_download` is defined externally there, not in this compose file.

```bash
# correct order
cd ~/homelab/services/media-download && docker compose up -d
cd ~/homelab/services/reading-library && docker compose up -d
```

## First run
### Kavita config

```bash
sudo mkdir -p /opt/appdata/kavita
```

### Suwayomi
World-writable required, do NOT use chown 1000:1000 here. 
Suwayomi's image expects arbitrary container UIDs to write to its data dirs.
This applies to Suwayomi's own appdata/downloads mount only — /mnt/media/manga,
the Kavita-facing output of the move script, keeps standard grim:grim ownership.

```bash
mkdir -p /mnt/media/suwayomi && chmod -R 777 /mnt/media/suwayomi
```

### Start 
(media-download must already be up — see Networking above)

```bash
docker compose up -d
```

### Logs

```bash
docker compose logs -f
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
3. Restart the container after adding the repo (`docker compose restart suwayomi`)
   to force a clean fetch
4. Install extensions: **Mangadex**, **Mangapill** (general), **Asura Scans**,
   **Webtoons** (manhwa)

5. **Settings → Downloads → enable "Save as CBZ"** in Suwayomi. Without this,
  chapters download as loose image folders with no reliable per-chapter
  archive — enabling it makes Suwayomi package each chapter as a proper
  `.cbz` with embedded `ComicInfo.xml`, which Kavita expects for clean
  per-file metadata and portability.
6. Confirm FlareSolverr is reachable if a source requires it (check
  `docker logs suwayomi` for FlareSolverr-related errors when a source
  fails to load).

## Migrating Kavita from another instance

To carry over user data, reading progress, and bookmarks, copy the config
directory from the source machine before starting the container.

```powershell
# On the source machine (Windows)
Compress-Archive -Path C:\homelab\kavita -DestinationPath C:\homelab\kavita-backup.zip
scp C:\homelab\kavita-backup.zip nat@kostyan-server.salmon-halfmoon.ts.net:/home/nat/kavita-backup.zip
```

```bash
# On target server
unzip ~/kavita-backup.zip -d ~/kavita-extract
sudo cp -r ~/kavita-extract/kavita/* /opt/appdata/kavita/

# Then start the container
docker compose up -d
```

## Known gotchas

- **Startup order**: this stack depends on `media-download/`'s
  `media_download` network existing. Bringing this stack up first fails
  Suwayomi with a network-not-found error.
- **Image version drift**: Kavita is pinned to `0.9.0`, not `latest` — always
  match container image version to database schema; `latest` can silently
  jump schema versions.
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