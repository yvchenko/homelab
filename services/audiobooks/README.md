# audiobooks

Self-hosted audiobook library with client-side caching for offline listening.



## Stack

| Service | Image | Notes |
|---|---|---|
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf:latest` | Single instance, nat-server only |

## Paths

| Path | Purpose |
|---|---|
| `/opt/appdata/audiobookshelf` | Config + metadata (runtime state) |
| `/mnt/media/audiobooks` | Library root |

## First run

```bash
chown -R 1000:1000 /opt/appdata/audiobookshelf /mnt/media/audiobooks
docker compose up -d
```

## Post-startup

1. Create admin account on first login
2. Add library, point to `/audiobooks`
3. Install app on iOS + Android, log in with same account, download books for offline playback — progress syncs automatically across devices

## Known gotchas

- Attaches to `media_download` (external) — `media-download/` must be up first if using Prowlarr/qBittorrent for acquisition
- Single-server-reads-local-storage — no remote/cross-node library serving, same limitation as Jellyfin
