# Prowlarr

Central indexer manager and single source of truth for torrent release search. Prowlarr doesn't download anything itself — it syncs indexers to Radarr/Sonarr for full automation, and doubles as the manual search/grab interface for media types without a dedicated arr app (manga, ranobe, danmei, comics).

## Access

| What | URL |
|---|---|
| Prowlarr (kostyan-server) | `http://kostyan-server.salmon-halfmoon.ts.net:9696` |
| Prowlarr (nat-server) | `http://nat-server.salmon-halfmoon.ts.net:9696` |
| qBittorrent | `http://kostyan-server.salmon-halfmoon.ts.net:8080` |

**Note:** readable-media categories (manga/ranobe/danmei/comics) are only relevant on kostyan-server — that's where Kavita lives. nat-server's Prowlarr instance is scoped to movies/TV only.

## Stack

| Service | Role |
|---|---|
| Prowlarr | Indexer aggregation, manual search, category routing to download client |
| Radarr | Movies — full automation (monitor, grab, import, rename) |
| Sonarr | TV — full automation (monitor, grab, import, rename) |
| qBittorrent | Download client, shared across all of the above + manual categories |

**No dedicated arr app for manga/ranobe/danmei/comics.** These are manual-grab workflows: search in Prowlarr → grab → lands in qBittorrent under a category → picked up by Kavita's own library scan. There is no monitoring/auto-grab layer for these types (Kapowarr was evaluated and rejected — no torrent/Usenet indexer support as of last check).

## Categories (qBittorrent)

| Category | Consumer | Save path | Automation level |
|---|---|---|---|
| `radarr` | Radarr | (Radarr-managed) | Full — monitor, grab, import |
| `sonarr` | Sonarr | (Sonarr-managed) | Full — monitor, grab, import |
| `manga` | Kavita (manual scan) | `/media/manga` | Manual grab; **default category for all readable-media releases regardless of actual type** |
| `ranobe` | Kavita (manual scan) | `/media/ranobe` | Manual grab + manual category reassignment (see gotchas) |
| `danmei` | Kavita (manual scan) | `/media/danmei` | Manual grab + manual category reassignment (see gotchas) |
| `comics` | Kavita (manual scan) | `/media/comics` | Same as manga/ranobe/danmei — manual grab + manual category reassignment |

## First startup

Adding indexers and hooking up Radarr/Sonarr as Apps is covered in the arr stack README — not repeated here. Once that's done:

1. Add qBittorrent as the **Download Client** in Prowlarr.
2. Under the qBittorrent download client settings, add **Mapped Categories** for `radarr` and `sonarr` (app-linked — Prowlarr routes grabs from these apps automatically).
3. In qBittorrent itself, manually create categories for `manga`, `ranobe`, `danmei`, `comics` with save paths pointed at `/media/<category>`. These are **not** app-linked — there's no auto-monitoring, grabs only land here when manually routed at grab time (see workflow below).

## Manual grab workflows

### Movies / TV

Nothing to do here manually — this is the whole point of running Radarr/Sonarr. Add the movie/show to the respective app, mark it monitored, and Prowlarr + the app handle search, grab, import, and renaming without intervention. If you ever want to grab a specific release yourself (e.g. a particular group's encode), use Radarr/Sonarr's own **Manual Search** on the title rather than Prowlarr's general search — that keeps the grab tied to the app's import pipeline so it still gets renamed/moved correctly.

### Manga / ranobe / danmei / comics

This is manual end to end, since there's no app playing the Radarr/Sonarr role for readable media:

1. **Search** in Prowlarr's search tab (or scoped to a specific indexer) for the title/volume/chapter you want.
2. **Grab** the release from the results list. Prowlarr sends it to qBittorrent using whatever category the indexer's own metadata resolves to — in practice, this defaults to `manga` for basically everything, regardless of whether it's actually a light novel or manhua/danmei, since most indexers don't distinguish these cleanly at the category level.
3. **Check qBittorrent** after the grab lands. If it's not actually manga, right-click the torrent → **Category** → reassign to `ranobe`, `danmei`, or `comics` as appropriate.
4. **Enable Automatic Torrent Management** on the torrent if it isn't already on by default — this is what actually makes the category reassignment move the files to the new category's save path. Without it, the category label changes but the files stay put (see gotchas).
5. Once the files are sitting in the correct `/media/<category>` folder, Kavita's own folder-watch/scan picks it up on its normal schedule — no manual rescan needed unless you want it immediately, in which case trigger a library scan from Kavita's UI.

Because this whole path is manual, there's no "new chapter dropped, auto-grabbed" experience like Sonarr gives you for TV. Checking for new releases and repeating steps 1–5 is a recurring, deliberate action, not a background job.

## Known gotchas

- **Indexer category granularity varies**: whatever indexer you use, its own category tagging for manga vs. light novels vs. danmei is generally coarser than the split we actually want in qBittorrent. Expect most readable-media grabs to default into `manga` and require the manual reassignment in step 3 above, regardless of which indexer it came from.
- **Category reassignment doesn't move files without AutoTMM**: qBittorrent's Edit Category dialog will show the new category's intended save path, but the torrent's actual `Save Path` (visible in the General tab) won't update unless Automatic Torrent Management is enabled for that torrent. Assigning a category after the fact is a label change only otherwise.