# media-sync

Cross-node file replication and co-viewing infrastructure between nat-server
(Spain) and kostyan-server (Ukraine), connected over the
`salmon-halfmoon.ts.net` tailnet.

- **syncthing** — replicates `shared/` and `cloud/` between both nodes,
  Send & Receive on both sides.
- **filebrowser** — Drive-like web UI over `cloud/`: upload, browse, and
  download from any device, no client install required.
- **syncplay** — relay server for synchronized local playback. Carries only
  play/pause/seek/position messages, never media bytes. Each side reads its
  own local, Syncthing-replicated copy of the file in VLC, keeping
  cross-country co-watching viable despite the Ukraine–Spain link.
- **samba** — SMB share over `shared/`, for client devices (laptops, etc.)
  that need direct network access to a node's local copy without running
  their own Syncthing instance.

Co-watching happens via VLC + Syncplay reading the synced file directly.
Native clients need to be downloaded separately according to device.

The Syncplay server only needs to run on one node — both clients connect to
that single instance regardless of which node hosts it.

## Stack

| Service     | Image                             | Purpose                                         |
| ----------- | ---------------------------------- | ------------------------------------------------ |
| syncthing   | `syncthing/syncthing:latest`       | Cross-node folder replication                   |
| filebrowser | `filebrowser/filebrowser:latest`   | Web upload/browse UI over `cloud/`              |
| syncplay    | `dnomd343/syncplay:latest`         | Playback-event relay for synced watching        |
| samba       | `dockurr/samba:latest`             | SMB share over `shared/` for non-synced devices |

## Paths

| Path                          | Purpose                                         |
| ------------------------------ | ------------------------------------------------ |
| `/opt/appdata/syncthing`       | Syncthing config and index database             |
| `/opt/appdata/filebrowser`     | Filebrowser SQLite database                     |
| `/opt/appdata/syncplay`        | Syncplay persistent room/stats data             |
| `/mnt/media/shared`            | Synced folder — co-viewing content              |
| `/mnt/media/cloud`             | Synced folder — general Drive-like storage      |
| `./filebrowser/settings.json`  | Filebrowser first-run baseline config (tracked) |

## First-run commands

```bash
cp .env.example .env
# Set PUID/PGID, NODE_NAME, SYNCPLAY_PASSWORD in .env

mkdir -p /mnt/media/shared /mnt/media/cloud
sudo mkdir -p /opt/appdata/syncthing /opt/appdata/filebrowser /opt/appdata/syncplay
sudo chown -R 1000:1000 /mnt/media/shared /mnt/media/cloud \
  /opt/appdata/syncthing /opt/appdata/filebrowser /opt/appdata/syncplay

docker compose up -d
```

## Post-startup steps

1. **Restrict the Syncthing GUI to Tailscale.** Because `syncthing` runs on
   `network_mode: host`, its GUI binds to all interfaces by default, not
   just `tailscale0`. Set `STGUIADDRESS` to the node's Tailscale IP before
   exposing this beyond localhost.

2. **Pair the two Syncthing instances.** On each node's Syncthing
   GUI: copy the device ID, add it as a remote device on the other node,
   accept the pairing request on both sides.

3. **Share both folders as Send & Receive, on both nodes.** Point them at
   the container paths (`/var/syncthing/shared`, `/var/syncthing/cloud`),
   not the host paths — the container only sees what is bind-mounted.

4. **Mirror the qBittorrent category on both nodes.** A `shared` category
   with its save path pointed at the local `shared/` folder, configured
   identically on nat-server's and kostyan-server's qBittorrent instances,
   since either node can originate a grab.

5. **Point Filebrowser's root at `/srv`** (already set in
   `filebrowser/settings.json`). Filebrowser generates a random admin
   password on first boot and prints it to the container logs — retrieve
   it with `docker compose logs filebrowser | grep -i password` and change
   it on first login.

6. **Verify Syncplay connectivity from both clients** before a watch
   session: Kostyan's Linux Syncplay client + VLC, and Synkplay on iOS
   (sideloaded via AltStore) — both pointed at whichever node hosts the
   relay. On iOS, use the VLCKit engine with a locally downloaded copy of
   the file (via the Samba share), not a direct SMB stream — see gotcha
   below.

## Known gotchas

- **Two-way folder conflicts.** With Send & Receive on both sides, if both
  nodes grab the same file independently around the same time, Syncthing
  creates a `.sync-conflict-<date>-<time>` copy rather than silently
  picking one. Check the folder before grabbing something to avoid
  duplicate downloads.
- **Filebrowser's `settings.json` only applies on first container start.**
  Edit it, then recreate the container
  (`docker compose up -d --force-recreate filebrowser`) for changes to
  take effect — a plain restart is not sufficient.
- **Filebrowser's admin credentials are auto-generated, not `admin`/`admin`.**
  Retrieve the generated password from the container logs on first boot;
  if the database already exists from a prior failed start, no new
  credentials are generated on restart and the password must be reset via
  `docker compose exec filebrowser filebrowser users update admin --password <new>`
  instead.
- **Syncplay has no persistent per-room auth.** `PASSWORD` in `.env` gates
  the entire server, not individual rooms — adequate for a two-person
  private server, not a substitute for real access control if this is ever
  exposed beyond Tailscale.
- **Samba's port 445 can conflict with a host-level `smbd`.** If Ubuntu's
  own Samba package is already installed and running, the container fails
  to start with `address already in use`. Stop and disable the host
  service (`sudo systemctl stop smbd`, `sudo systemctl disable smbd`) if
  nothing else on that node depends on it.
- **`SAMBA_HOST_IP` must be set explicitly in `.env`.** It binds port 445
  to that single address rather than all interfaces — leaving it blank
  exposes SMB beyond the tailnet.
- **Synkplay's VLCKit engine reports a broken seek position when playing
  directly off the Samba SMB share on iOS**, which Syncplay then
  interprets as a real seek and rewinds the whole room to 00:00. Confirmed
  specific to VLCKit + SMB — the same engine seeks correctly on a local
  file, and the native desktop Syncplay + VLC client has no issue with the
  same SMB source. Tracked upstream:
  [yuroyami/syncplay-mobile#158](https://github.com/yuroyami/syncplay-mobile/issues/158).
  Workaround: download the episode to the iPad locally (via the Files app,
  from the Samba share) before a watch session, and open that local copy
  in Synkplay's VLCKit engine instead of streaming it live.