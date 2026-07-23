# audiobooks

Self-hosted audiobook library with client-side caching for offline listening.

## Access

| Service        | URL                                              |
| -------------- | ------------------------------------------------ |
| Audiobookshelf | `http://nat-server.salmon-halfmoon.ts.net:13378` |

## Stack

| Service        | Image                                   | Notes                            |
| -------------- | --------------------------------------- | -------------------------------- |
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf:latest` | Single instance, nat-server only |

## Paths

| Path                               | Purpose                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------ |
| `/opt/appdata/audiobookshelf`      | Config + metadata (runtime state)                                              |
| `/mnt/media/audiobooks`            | Library root                                                                   |
| `prowlarr-custom/audiobookbay.yml` | Custom Cardigann indexer definition, mounted into Prowlarr (`media-download/`) |

## First run

```bash
chown -R 1000:1000 /opt/appdata/audiobookshelf /mnt/media/audiobooks
docker compose up -d
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

Prowlarr (`media-download/`) handles indexer search; qBittorrent handles the grab.

* **AudioBookBay** — no official Prowlarr definition (excluded from Prowlarr's supported-indexers blocklist, though still present upstream in Jackett's). A custom Cardigann YAML is kept at `prowlarr-custom/audiobookbay.yml`, sourced from Jackett's maintained definition and mounted read-only into Prowlarr:

  ```yaml
  volumes:
    - ../audiobooks/prowlarr-custom/audiobookbay.yml:/config/Definitions/Custom/audiobookbay.yml:ro
  ```

  **Status: currently unreliable, not actively used.** The site's domain (`audiobookbay.lu`) rotates and has inconsistent global uptime independent of any local config. Current workaround: manually download `.torrent`/magnet links from the site and add directly to qBittorrent. Revisit automation if the site stabilizes on a working mirror — flip the `Base Url` in Prowlarr's indexer settings and it should pick back up with no other changes needed.

* **qBittorrent category** — tag audiobook downloads (manual or automated) with a dedicated `audiobooks` category in qBittorrent, save path pointed at `/mnt/media/audiobooks` staging. Keeps them out of the general/arr-stack download flow and easy to filter, same reasoning as the readable-media categories on kostyan-server.

## Known gotchas

* Attaches to `media_download` (external) — `media-download/` must be up first if using Prowlarr/qBittorrent for acquisition.
* Single-server-reads-local-storage — no remote/cross-node library serving, same limitation as Jellyfin.
* Custom Prowlarr indexer definitions require a container recreate (`docker compose up -d --force-recreate prowlarr`), not just a restart, to pick up new/changed mounts.
