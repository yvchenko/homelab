# Media Acquisition (Prowlarr / Radarr / Sonarr / qBittorrent)

Usage instructions for the full acquisition path, not a service-by-service setup guide — covers how a search actually turns into a file landing in the right library. Prowlarr is the indexer aggregator; it doesn't download anything itself. For movies/TV, Radarr/Sonarr own the workflow end to end (Prowlarr just feeds them indexers). For media types without a dedicated arr app (manga, ranobe, danmei, comics), Prowlarr's own search/grab tab is the interface, and everything past the grab is manual.

## Access

| What | URL |
|---|---|
| Prowlarr (kostyan-server) | `http://kostyan-server.salmon-halfmoon.ts.net:9696` |
| Prowlarr (nat-server) | `http://nat-server.salmon-halfmoon.ts.net:9696` |
| Radarr (kostyan-server) | `http://kostyan-server.salmon-halfmoon.ts.net:7878` |
| Radarr (nat-server) | `http://nat-server.salmon-halfmoon.ts.net:7878` |
| Sonarr (kostyan-server) | `http://kostyan-server.salmon-halfmoon.ts.net:8989` |
| Sonarr (nat-server) | `http://nat-server.salmon-halfmoon.ts.net:8989` |
| qBittorrent | `http://kostyan-server.salmon-halfmoon.ts.net:8080` |

*(Radarr/Sonarr ports above are the arr-stack defaults — confirm and correct if either instance was reconfigured.)*

**Note:** readable-media categories (manga/ranobe/danmei/comics) are only relevant on kostyan-server — that's where Kavita lives. nat-server's Prowlarr instance is scoped to movies/TV only.

## Stack

| Service | Role |
|---|---|
| Prowlarr | Indexer aggregation; feeds Radarr/Sonarr automatically; manual search/grab UI for media types with no dedicated arr app |
| Radarr | Movies — full automation (monitor, search, grab, import, rename) via indexers synced from Prowlarr |
| Sonarr | TV — full automation (monitor, search, grab, import, rename) via indexers synced from Prowlarr |
| qBittorrent | Download client, shared across all of the above + manual categories |

**No dedicated arr app for manga/ranobe/danmei/comics.** These are manual-grab workflows: search in Prowlarr → grab → lands in qBittorrent under a category → picked up by Kavita's own library scan. There is no monitoring/auto-grab layer for these types (Kapowarr was evaluated and rejected — no torrent/Usenet indexer support as of last check).

## Categories (qBittorrent)

| Category | Consumer | Save path | Automation level |
|---|---|---|---|
| `radarr` | Radarr | (Radarr-managed) | Full — monitor, search, grab, import |
| `sonarr` | Sonarr | (Sonarr-managed) | Full — monitor, search, grab, import |
| `manga` | Kavita (manual scan) | `/media/manga` | Manual grab; **default category for all readable-media releases regardless of actual type** |
| `ranobe` | Kavita (manual scan) | `/media/ranobe` | Manual grab + manual category reassignment (see gotchas) |
| `danmei` | Kavita (manual scan) | `/media/danmei` | Manual grab + manual category reassignment (see gotchas) |
| `comics` | Kavita (manual scan) | `/media/comics` | Same as manga/ranobe/danmei — manual grab + manual category reassignment |

## First startup

Adding indexers and hooking up Radarr/Sonarr as Apps is covered in the arr stack README — not repeated here. Once that's done:

1. Add qBittorrent as the **Download Client** in Prowlarr.
2. Under the qBittorrent download client settings, add **Mapped Categories** for `radarr` and `sonarr` (app-linked — Prowlarr routes grabs from these apps automatically).
3. In qBittorrent itself, manually create categories for `manga`, `ranobe`, `danmei`, `comics` with save paths pointed at `/media/<category>`. These are **not** app-linked — there's no auto-monitoring, grabs only land here when manually routed at grab time (see workflow below).
4. In Radarr and Sonarr, confirm **Completed Download Handling** is enabled (Settings → Download Clients → top of page). Without this, neither app will notice or import finished downloads even if the category is correct.

## Manual grab workflows

### Movies / TV

This is Radarr/Sonarr-driven, not Prowlarr-driven — Prowlarr just supplies the indexers underneath.

1. **Add** the movie/show to Radarr/Sonarr. Mark it monitored, and confirm **Search on Add** is enabled (either globally in Settings → General, or as a per-add toggle) — this makes the app immediately search all Prowlarr-synced indexers, grab the best match per your quality profile, and send it to qBittorrent tagged with the `radarr`/`sonarr` category.
2. **Import happens automatically.** Completed Download Handling polls the category, matches the finished file's parsed filename against the library entry, then hardlinks/renames/moves it into place. No manual import step for the normal case.
3. **Overriding the auto-grab:** if you want a specific release (different group, quality, etc.) instead of what auto-search picked, use Radarr/Sonarr's own **Interactive Search** on that title — not Prowlarr's search tab. Interactive Search still ties the grab back to the library entry, so import/rename still happens automatically. Grabbing the same release via Prowlarr's general search tab instead would skip that link and dump an unmanaged file in qBittorrent.
4. **One-off, don't-care-about-organizing downloads:** Prowlarr's own Search tab (magnifying glass, top nav) can grab and send to qBittorrent directly, with no Radarr/Sonarr entry involved. Use this only when you don't want the file tracked in your library — there's no automatic import, renaming, or hardlinking on this path, and no reverse mechanism where an unrecognized file creates a library entry on its own. Organizing it afterward is entirely manual.

### Manga / ranobe / danmei / comics

This is manual end to end, since there's no app playing the Radarr/Sonarr role for readable media:

1. **Search** in Prowlarr's search tab (or scoped to a specific indexer) for the title/volume/chapter you want.
2. **Grab** the release from the results list. Prowlarr sends it to qBittorrent using whatever category the indexer's own metadata resolves to — in practice, this defaults to `manga` for basically everything, regardless of whether it's actually a light novel or manhua/danmei, since most indexers don't distinguish these cleanly at the category level.
3. **Check qBittorrent** after the grab lands. If it's not actually manga, right-click the torrent → **Category** → reassign to `ranobe`, `danmei`, or `comics` as appropriate.
4. **Enable Automatic Torrent Management** on the torrent if it isn't already on by default — this is what actually makes the category reassignment move the files to the new category's save path. Without it, the category label changes but the files stay put (see gotchas).
5. Once the files are sitting in the correct `/media/<category>` folder, Kavita's own folder-watch/scan picks it up on its normal schedule — no manual rescan needed unless you want it immediately, in which case trigger a library scan from Kavita's UI.

Because this whole path is manual, there's no "new chapter dropped, auto-grabbed" experience like Sonarr gives you for TV. Checking for new releases and repeating steps 1–5 is a recurring, deliberate action, not a background job.

## Known gotchas

- **Radarr/Sonarr can't create their own library entries.** Matching requires the movie/show to already exist in the app's database (monitored or not) — there's no path where dropping an unrecognized file in the download folder makes Radarr/Sonarr look it up and add itself. If you want zero-touch import, the entry has to exist before the grab.
- **Indexer category granularity varies**: whatever indexer you use, its own category tagging for manga vs. light novels vs. danmei is generally coarser than the split we actually want in qBittorrent. Expect most readable-media grabs to default into `manga` and require the manual reassignment in step 3 above, regardless of which indexer it came from.
- **Category reassignment doesn't move files without AutoTMM**: qBittorrent's Edit Category dialog will show the new category's intended save path, but the torrent's actual `Save Path` (visible in the General tab) won't update unless Automatic Torrent Management is enabled for that torrent. Assigning a category after the fact is a label change only otherwise.
- **Completed Download Handling is a separate toggle from the download client connection itself** — easy to have qBittorrent connected in Radarr/Sonarr but this switch off, in which case nothing auto-imports even with the right category.
