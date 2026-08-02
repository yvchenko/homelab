# audiobooks

Self-hosted audiobook library with client-side caching for offline listening.

## Stack

| Service        | Image                                   | Notes                                       |
| -------------- | ---------------------------------------- | -------------------------------------------- |
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf:latest`  | Single instance, nat-server only (`disk: nat-media`) |

Runs as a k8s Deployment in the `audiobooks` namespace. `hostPort: 13378` exposes the WebUI directly on the node's Tailscale IP, same reachability as before — no ingress/reverse-proxy involved.

## Paths

| Path                          | Purpose                            |
| ----------------------------- | ----------------------------------- |
| `/opt/appdata/audiobookshelf` | Config + metadata (runtime state), mounted via `hostPath` |
| `/mnt/media/audiobooks`       | Library root, mounted via `hostPath` |

Note: this service does **not** attach to `media_download` — that network reference existed in the original Compose file but was never actually load-bearing (Audiobookshelf itself has no Prowlarr/qBittorrent integration), so it was dropped entirely in the k8s manifest.

## First run

```bash
chown -R 1000:1000 /opt/appdata/audiobookshelf /mnt/media/audiobooks
sudo k3s kubectl create namespace audiobooks
sudo k3s kubectl apply -f services/audiobooks/audiobookshelf/manifest.yaml
sudo k3s kubectl get pods -n audiobooks -o wide
```

## Post-startup

1. Create an admin account on first login.
2. Add a library, pointing it to `/audiobooks`.

## Client apps

| Platform | Recommended app               |
| -------- | ----------------------------- |
| Android  | Audiobookshelf (official app) |
| iOS      | ShelfPlayer                   |

### Connecting

1. Install the client app for your platform.
2. Add a new server.
3. Enter the server URL:

   ```
   http://nat-server.salmon-halfmoon.ts.net:13378
   ```
4. Log in with your Audiobookshelf username and password.
5. Download books for offline playback if desired. Listening progress, bookmarks, and playback position will sync automatically across devices whenever they reconnect to the server.

## Acquisition

Prowlarr (`media-download/`) handles indexer search; qBittorrent handles the grab. Both run as their own k8s workloads (DaemonSets in the `media-download` namespace) — no dependency ordering needed at the manifest level for this service, since Audiobookshelf itself doesn't talk to either directly.

* **AudioBookBay** — no official Prowlarr definition (excluded from Prowlarr's supported-indexers blocklist, though still present upstream in Jackett's). A custom Cardigann YAML is kept at `prowlarr-custom/audiobookbay.yml`, sourced from Jackett's maintained definition and mounted into Prowlarr's pod via a `hostPath` volume pointing at the file directly (see `media-download/`'s manifest — Prowlarr's `custom-indexer` volume).

  **Status: currently unreliable, not actively used.** The site's domain (`audiobookbay.lu`) rotates and has inconsistent global uptime independent of any local config. Current workaround: manually download `.torrent`/magnet links from the site and add directly to qBittorrent. Revisit automation if the site stabilizes on a working mirror — flip the `Base Url` in Prowlarr's indexer settings and it should pick back up with no other changes needed.

* **qBittorrent category** — tag audiobook downloads (manual or automated) with a dedicated `audiobooks` category in qBittorrent, save path pointed at `/mnt/media/audiobooks` staging. Keeps them out of the general/arr-stack download flow and easy to filter, same reasoning as the readable-media categories on kostyan-server.

## Known gotchas

* Single-node reads local storage only — no remote/cross-node library serving, same limitation as Jellyfin.
* Picking up changes to the custom Prowlarr indexer file requires deleting Prowlarr's pod (`kubectl delete pod <prowlarr-pod-name> -n media-download`) to force a fresh mount read, not just editing the file in place — a running pod won't pick up a changed hostPath-mounted file automatically.
* If the custom indexer file (`prowlarr-custom/audiobookbay.yml`) is missing on a given node when Prowlarr's pod is scheduled there, the pod will fail to start (`hostPath type check failed: ... is not a file`) rather than silently skipping it — make sure the repo is pulled on whichever node Prowlarr's about to (re)start on before applying changes.
