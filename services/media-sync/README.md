# media-sync

Cross-node file replication and co-viewing infrastructure between nat-server
(Spain) and kostyan-server (Ukraine), tied together over the
`salmon-halfmoon.ts.net` tailnet. Three services, one cluster, because all
three exist to serve the same domain — getting the same bytes and the same
playback state onto both nodes — and depend on each other in practice even
though they don't share a Docker network requirement.

- **syncthing** — replicates `shared/` and `cloud/` between
  both nodes, Send & Receive on both sides.
- **filebrowser** — Drive-like web UI over `cloud/`: upload/browse
  from any device, no client install required.
- **syncplay** — relay server for synced local playback. Only ever carries
  play/pause/seek/position messages — never media bytes. This is what makes
  cross-country co-watching viable despite the Ukraine–Spain link; each side
  reads its own local, Syncthing-replicated copy.

`video` (Jellyfin) consumes the `shared/` folder as an additional
library source, same relationship `reading-library` has with
`media-download`: `media-sync` must be up first, or the library has nothing
to index on first boot.

## Access

| Service            | kostyan-server                                          | nat-server                                          |
| ------------------ | -------------------------------------------------------- | ---------------------------------------------------- |
| Syncthing GUI       | `http://kostyan-server.salmon-halfmoon.ts.net:8384`      | `http://nat-server.salmon-halfmoon.ts.net:8384`      |
| Filebrowser         | `http://kostyan-server.salmon-halfmoon.ts.net:8082`      | `http://nat-server.salmon-halfmoon.ts.net:8082`      |
| Syncplay server     | `kostyan-server.salmon-halfmoon.ts.net:8999` (TCP, no UI)| `nat-server.salmon-halfmoon.ts.net:8999` (TCP, no UI)|

Run the Syncplay server on whichever node you actually want to be the
gathering point — both of you connect your clients to that one instance, you
don't need it running on both nodes.

## Stack

| Service     | Image                        | Purpose                                             |
| ----------- | ----------------------------- | ---------------------------------------------------- |
| syncthing   | `syncthing/syncthing:latest`  | Cross-node folder replication                        |
| filebrowser | `filebrowser/filebrowser:latest` | Web upload/browse UI over `cloud/`         |
| syncplay    | `dnomd343/syncplay:latest`    | Playback-event relay for synced watching             |

## Paths

| Path                            | Purpose                                          |
| -------------------------------- | ------------------------------------------------- |
| `/opt/appdata/syncthing`         | Syncthing config + index database                 |
| `/opt/appdata/filebrowser`       | Filebrowser SQLite database                        |
| `/opt/appdata/syncplay`          | Syncplay persistent room/stats data                |
| `/mnt/media/shared`      | Synced folder — co-viewing content                 |
| `/mnt/media/cloud`       | Synced folder — general Drive-like storage         |
| `./filebrowser/settings.json`    | Filebrowser first-run baseline config (tracked)    |

## First-run commands

```bash
cp .env.example .env
# edit .env: PUID/PGID, NODE_NAME, SYNCPLAY_PASSWORD

mkdir -p /mnt/media/shared /mnt/media/cloud
chown -R ${PUID}:${PGID} /mnt/media/shared /mnt/media/cloud

docker compose up -d
```

## Post-startup steps

1. **Restrict the Syncthing GUI to Tailscale.** Because `syncthing` runs on
   `network_mode: host`, its GUI binds to all interfaces by default — not
   just `tailscale0`. Set `STGUIADDRESS` (or edit `config.xml` under
   `/opt/appdata/syncthing`) to the node's Tailscale IP before exposing this
   anywhere. Same reasoning as Dante's tailscale0-only bind in
   `media-download`.

2. **Pair the two Syncthing instances.** This is a manual, mutual
   bootstrapping step — nothing in git can do this for you, since each
   daemon generates its own device ID at first boot. On each node's
   Syncthing GUI: copy the device ID, add it as a remote device on the
   other node, accept the pairing request on both sides.

3. **Share both folders as Send & Receive, on both nodes.** Point them at
   the container paths (`/var/syncthing/shared`,
   `/var/syncthing/cloud`), not the host paths — the container
   only sees what's bind-mounted.

4. **Mirror the qBittorrent category on both nodes.** `shared` as a
   category, save path pointed at the local `shared/` folder, on
   both nat-server's and kostyan-server's qBittorrent — since either of you
   can now originate a grab.

5. **Add `shared/` as a Jellyfin library** on whichever node's
   Jellyfin you'll browse it from.

6. **Point Filebrowser's root at `/srv`** (already set in
   `filebrowser/settings.json`) and create your user account on first login
   — default is `admin`/`admin`, change it immediately.

7. **Test Syncplay connectivity from both clients** before movie night:
   Kostyan's Linux Syncplay + mpv/VLC, your Synkplay (iOS, sideloaded via
   AltStore) — both pointed at whichever node is hosting the relay.

## Known gotchas

- **Syncthing sync ≠ instant.** The full file has to physically cross the
  Ukraine–Spain Tailscale link before the receiving side has anything to
  play. Grab well ahead of when you actually want to watch — this isn't
  something Syncplay's lightweight relay can paper over.
- **Two-way folder conflicts.** With Send & Receive on both sides, if you
  and Kostyan grab the same file independently around the same time,
  Syncthing creates a `.sync-conflict-<date>-<time>` copy rather than
  silently picking one. Rare for a "different episodes" folder, but glance
  at the folder before grabbing something to avoid duplicate downloads.
- **Filebrowser's `settings.json` only applies on first container start.**
  Same category of gotcha as qBittorrent's config — edit it, then remove
  and recreate the container (`docker compose up -d --force-recreate
  filebrowser`) for changes to take effect, not just a restart.
- **Syncplay has no persistent auth beyond the room password.** `PASSWORD`
  in `.env` gates the whole server, not per-room — fine for a two-person
  private server, but don't treat it as strong access control if this ever
  gets exposed beyond Tailscale.
- **Syncthing GUI defaults to all interfaces under `network_mode: host`.**
  See post-startup step 1 — don't skip it before this is reachable outside
  the tailnet.
