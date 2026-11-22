# media-sync

Cross-node file replication and co-viewing infrastructure between nat-server
(Spain) and kostyan-server (Ukraine), connected over the
`salmon-halfmoon.ts.net` tailnet.

- **syncthing** — replicates `shared/` and `cloud/` between both nodes,
  Send & Receive on both sides.
- **nextcloud** — Drive-like web UI (plus desktop/mobile sync clients) over
  `cloud/`, which it mounts as Local external storage so Syncthing stays the
  replication layer.
- **syncplay** — relay server for synchronized local playback. Carries only
  play/pause/seek/position messages, never media bytes. Each side reads its
  own local, Syncthing-replicated copy of the file in VLC, keeping
  cross-country co-watching viable despite the Ukraine–Spain link.
- **samba** — SMB share over `shared/`, for client devices (laptops, etc.)
  that need direct network access to a node's local copy without running
  their own Syncthing instance.

Co-watching happens via VLC + Syncplay reading the synced file directly.
Native clients need to be downloaded separately according to device.

The Syncplay server runs on **both** nodes independently (matching the
homelab's general per-node-independence philosophy) rather than one shared
instance — each side's client connects to its own node's relay.

## Stack

| Service     | Image                             | Purpose                                         | k8s primitive |
| ----------- | ---------------------------------- | ------------------------------------------------ | -------------- |
| syncthing   | `syncthing/syncthing:latest`       | Cross-node folder replication                   | Kustomize base + per-node overlay |
| nextcloud   | `lscr.io/linuxserver/nextcloud:latest` + `postgres:17-alpine` sidecar | Web/sync-client UI over `cloud/` | DaemonSet |
| syncplay    | `dnomd343/syncplay:latest`         | Playback-event relay for synced watching        | DaemonSet |
| samba       | `dockurr/samba:latest`             | SMB share over `shared/` for non-synced devices | Kustomize base + per-node overlay |

All run in the `media-sync` namespace, one pod per node for every service
(shared node label `media-sync=true` for the two DaemonSets; per-node
`disk=nat-media` / `disk=kostyan-media` labels for the Kustomize overlays,
same labels used across the whole homelab).

**Syncthing and Samba use Kustomize** because their pod specs genuinely
differ per node (hostname suffix/timezone for Syncthing; bind IP and
credentials for Samba) — same base+overlay pattern used for Jellyfin.
**Nextcloud and Syncplay are plain DaemonSets**, since neither has any
per-node configuration difference in the pod spec; the shared
`media-sync=true` label is enough to run one identical pod on each node.
Each node's Nextcloud is fully independent (own users, own database, own
config) — only the files under `cloud/` are shared, via Syncthing.

## Paths

| Path                          | Purpose                                         |
| ------------------------------ | ------------------------------------------------ |
| `/opt/appdata/syncthing`       | Syncthing config and index database             |
| `/opt/appdata/nextcloud/config` | Nextcloud app + `config.php`                   |
| `/opt/appdata/nextcloud/data`   | Nextcloud data dir (per-user home folders)     |
| `/opt/appdata/nextcloud/db`     | Postgres sidecar data                          |
| `/opt/appdata/syncplay`        | Syncplay persistent room/stats data             |
| `/mnt/media/shared`            | Synced folder — co-viewing content              |
| `/mnt/media/cloud`             | Synced folder — general Drive-like storage      |

All mounted via `hostPath`. Nextcloud's `/mnt/media/cloud` mount uses
`type: Directory`, so if the folder is ever missing the pod fails to start
instead of kubelet silently fabricating an empty `root:root` dir in its
place (the failure mode behind the 2026-09-12 `cloud/` data loss).

## Secrets

Credentials no longer live in `.env` — every sensitive value is a real k8s
`Secret`, created imperatively, never committed:

```bash
sudo k3s kubectl create secret generic syncplay-credentials \
  --namespace media-sync \
  --from-literal=PASSWORD='...'

sudo k3s kubectl create secret generic samba-credentials-nat \
  --namespace media-sync \
  --from-literal=USER='nat' \
  --from-literal=PASS='...'

sudo k3s kubectl create secret generic samba-credentials-kostyan \
  --namespace media-sync \
  --from-literal=USER='grim' \
  --from-literal=PASS='...'

sudo k3s kubectl create secret generic nextcloud-db-credentials \
  --namespace media-sync \
  --from-literal=POSTGRES_PASSWORD='...'
```

The Nextcloud DB password is only read by the Postgres sidecar; you type the
same value into Nextcloud's first-run wizard (see Post-startup steps).

**Samba's Secret keys must be named `USER`/`PASS`, not `USER`/`PASSWORD`.**
The `dockurr/samba` image specifically expects an env var literally named
`PASS` — using `PASSWORD` (the naming convention used everywhere else in
this migration) silently fails: the container starts fine and just
authenticates against its own internal default value instead of ever
seeing the real password, with no error in the logs. Verify with
`kubectl exec <pod> -- env | grep -i "user\|pass"` if login ever behaves
like this again — you're looking for exactly `USER=...` and `PASS=...`,
nothing else.

`PASSWORD` (not `PASS`) is correct for Syncplay's Secret — different image,
different expected variable name.

## First-run commands

```bash
sudo k3s kubectl label node nat-server media-sync=true
sudo k3s kubectl label node gwserver media-sync=true

mkdir -p /mnt/media/shared /mnt/media/cloud
sudo mkdir -p /opt/appdata/syncthing /opt/appdata/syncplay \
  /opt/appdata/nextcloud/config /opt/appdata/nextcloud/data /opt/appdata/nextcloud/db
sudo chown -R 1000:1000 /mnt/media/shared /mnt/media/cloud \
  /opt/appdata/syncthing /opt/appdata/syncplay /opt/appdata/nextcloud

sudo k3s kubectl create namespace media-sync
# ...create the Secrets from above...

sudo k3s kubectl apply -f services/media-sync/nextcloud/manifest.yaml
sudo k3s kubectl apply -f services/media-sync/syncplay/manifest.yaml
sudo k3s kubectl apply -k services/media-sync/syncthing/overlays/nat
sudo k3s kubectl apply -k services/media-sync/syncthing/overlays/kostyan
sudo k3s kubectl apply -k services/media-sync/samba/overlays/nat
sudo k3s kubectl apply -k services/media-sync/samba/overlays/kostyan
sudo k3s kubectl get pods -n media-sync -o wide
```

## Networking

**Syncthing and Syncplay** run with `hostNetwork: true` — needed for
Syncthing's transfer/local-discovery ports and Syncplay's documented
`--net=host` requirement.

**Samba deliberately does *not* use `hostNetwork: true`.** The original
Compose config bound port 445 to one specific IP (`SAMBA_HOST_IP`, each
node's own Tailscale address) — Docker enforced this by only publishing the
port on that interface. `hostNetwork: true` would silently destroy that
restriction: the pod's `0.0.0.0:445` listener would bind to the *entire
host*, including the LAN, not just the tailnet — a real security
regression, not just a config nuance. The correct k8s translation is a
`hostPort` + explicit `hostIP` on the container port spec instead, set
per-node in each Samba overlay:

```yaml
ports:
- containerPort: 445
  hostPort: 445
  hostIP: 100.83.164.52   # this node's own Tailscale IP
```

This preserves the exact same tailnet-only binding Docker's `SAMBA_HOST_IP`
was enforcing — the pod keeps its own network namespace, only the
host-side port publish is IP-restricted.

**Nextcloud** uses a plain `hostPort: 8082` (the port Filebrowser used to
have), no IP restriction. The Postgres sidecar runs with
`listen_addresses=localhost`, so it's only reachable from inside the pod.

## Post-startup steps

1. **Restrict the Syncthing GUI to Tailscale.** Because `syncthing` runs
   with `hostNetwork: true`, its GUI binds to all interfaces by default,
   not just `tailscale0`. Set `STGUIADDRESS` to the node's Tailscale IP
   before exposing this beyond localhost.

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

5. **Run Nextcloud's first-run wizard on each node** at
   `http://<node>.salmon-halfmoon.ts.net:8082`: create the admin account,
   pick **PostgreSQL**, user `nextcloud`, password from
   `nextcloud-db-credentials`, database `nextcloud`, host `localhost`.
   Leave the data folder as `/data`. The hostname you open the wizard from
   is added to `trusted_domains` automatically.

6. **Mount `cloud/` as external storage.** Apps → enable *External storage
   support*, then Administration → External storage: add a **Local** mount,
   folder name `cloud`, configuration `/cloud`, available for the users who
   should see it. Under its advanced options set *Check for changes* to
   **Once every direct access** so files Syncthing drops in show up without
   a manual `occ files:scan`.

7. **Verify Syncplay connectivity from both clients** before a watch
   session: Kostyan's Linux Syncplay client + VLC, and Synkplay on iOS
   (sideloaded via AltStore) — each pointed at its own node's relay. On
   iOS, use the VLCKit engine with a locally downloaded copy of the file
   (via the Samba share), not a direct SMB stream — see gotcha below.

## Known gotchas

- **Nextcloud can't skip major versions on upgrade.** The linuxserver image
  is on `:latest`, and an image bump that jumps more than one Nextcloud major
  (e.g. after the node sat un-updated for a long time) leaves the instance
  refusing to start its upgrade. If that happens, pin the image to the next
  major's tag, let it upgrade, then step forward. Same idea for the
  `postgres:17` sidecar: a Postgres major bump needs a dump/restore, so that
  tag is deliberately pinned.

- **`occ` must run as the `abc` user.** Running it as root fails or leaves
  root-owned files under `/config`:
  ```bash
  sudo k3s kubectl exec -n media-sync <nextcloud-pod> -c nextcloud -- \
    occ files:scan --all
  ```
  (linuxserver's image ships an `occ` wrapper that already switches to
  `abc`.)

- **Files under `cloud/` only appear via the external-storage mount, not
  in users' home folders.** Uploading to a user's own space writes to
  `/opt/appdata/nextcloud/data`, which Syncthing does *not* replicate.
  Upload into the `cloud` folder for anything that should exist on both
  nodes.

- **Two-way folder conflicts.** With Send & Receive on both sides, if both
  nodes grab the same file independently around the same time, Syncthing
  creates a `.sync-conflict-<date>-<time>` copy rather than silently
  picking one. Check the folder before grabbing something to avoid
  duplicate downloads.

- **Syncplay has no persistent per-room auth.** `PASSWORD` in the Secret
  gates the entire server, not individual rooms — adequate for a
  two-person private server, not a substitute for real access control if
  this is ever exposed beyond Tailscale.

- **Samba's port 445 can conflict with a host-level `smbd`.** If Ubuntu's
  own Samba package is already installed and running, the pod's `hostPort`
  binding fails with `address already in use`. Stop and disable the host
  service (`sudo systemctl stop smbd`, `sudo systemctl disable smbd`) if
  nothing else on that node depends on it.

- **Samba's env var name must be exactly `PASS`, not `PASSWORD`.** See the
  Secrets section above — this is the one service in the migration whose
  image doesn't follow the `USER`/`PASSWORD` naming convention used
  elsewhere, and the failure mode (silent auth against a default value,
  no error) makes it easy to miss.

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
