# Suwayomi

Manga/manhwa downloader and library manager. Downloads chapters from web sources (Mangadex, Mangapill, Asura Scans, Webtoons, etc.) as flat image folders and writes a `ComicInfo.xml` into each chapter with full metadata (series, summary, writer, genres) pulled from the source. 

Suwayomi uses the Tachiyomi/Mihon extension ecosystem instead — actively maintained, much broader source coverage.

Suwayomi's own download layout (`<source-site>/<series-name>`) is not something Kavita or Komga can scan directly as a library — it needs to be flattened to `<series-name>` first. See [Post-download library sync](#post-download-library-sync) below.

## Stack

| Component | Image | Notes |
|---|---|---|
| Suwayomi | `ghcr.io/suwayomi/suwayomi-server:stable` |

## Paths

| Host | Container | Purpose |
|---|---|---|
| `/mnt/media/suwayomi` | `/home/suwayomi/.local/share/Tachidesk/downloads` | Downloaded chapters — **must be first volume entry** (Suwayomi requirement) |
| `/opt/appdata/suwayomi` | `/home/suwayomi/.local/share/Tachidesk` | App config, database, extensions, thumbnails |

Downloads land at `/mnt/media/suwayomi/mangas/<Source Name>/<Manga Title>/<chapter folder>`. 

## Post-download library sync

Suwayomi and Komga expect different folder structures, so downloads are staged separately and flattened by a script rather than downloaded directly into the Komga library:

| Path | Purpose |
|---|---|
| `/mnt/media/suwayomi/mangas/<source-site>/<series-name>/` | Suwayomi's own download structure (staging area, not a library) |
| `/mnt/media/manga/<series-name>/` | Flat per-series structure Komga scans as a library |

**Script**: `tools/scripts/suwayomi-move.sh`

- Merges all source-site variants of a series into one destination folder (e.g. a series downloaded from both Mangadex and Asura Scans lands in a single `/mnt/media/manga/<series-name>/` folder)
- Files are **moved**, not copied — Suwayomi's originals are not preserved to avoid file clutter
- Cleans up empty source-site folders under `/mnt/media/suwayomi/mangas/` after each run
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

Attached to the `arr_arr` network so it can reach FlareSolverr by container name (`http://flaresolverr:8191`).

## First-run setup

1. `mkdir -p /mnt/media/suwayomi && chmod -R 777 /mnt/media/suwayomi` (Suwayomi's image expects world-writable data dirs to support arbitrary container UIDs — do not use the `chown 1000:1000` pattern here). Note this applies to the Suwayomi appdata/downloads mount specifically — `/mnt/media/manga` (the Komga-facing output of the move script) follows the standard `grim:grim` ownership used elsewhere under `/mnt/media` on gwserver, not this rule.
2. `docker compose up -d`
3. Open the web UI → **Browse → Extension → Settings → Extension repositories**
4. Add repo using the **raw JSON URL**, not the GitHub landing page:
   ```
   https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json
   ```
   (the shorthand `https://github.com/keiyoushi/extensions` form throws a `ProtobufDecodingException` on the current Extension Store system — use the raw URL)
5. Restart the container after adding the repo (`docker compose restart suwayomi`) to force a clean fetch
6. Install extensions: **Mangadex**, **Mangapill** (general), **Asura Scans**, **Webtoons** (manhwa)

## Post-setup — required

- **Settings → Downloads → enable "Save as CBZ"**. Without this, chapters download as loose image folders with no reliable per-chapter archive — enabling it makes Suwayomi package each chapter as a proper `.cbz` with embedded `ComicInfo.xml`, which is what downstream readers (Kavita/Komga) expect for clean per-file metadata and portability.
- Confirm FlareSolverr is reachable if a source requires it (check `docker logs suwayomi` for FlareSolverr-related errors when a source fails to load).