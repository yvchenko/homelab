# Jellyfin

Self-hosted media server. Serves
media stored on the HDD mount at `/mnt/media`.

## Access

| Interface | URL |
|-----------|-----|
| Web UI | http://kostyan-server.salmon-halfmoon.ts.net:8096 |

Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image |
|-----------|-------|
| Media server | `jellyfin/jellyfin:latest` |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Config | `/opt/appdata/jellyfin/config` | `/config` |
| Cache | `/opt/appdata/jellyfin/cache` | `/cache` |
| Movies | `/mnt/media/movies` | `/media/movies` |
| TV | `/mnt/media/tv` | `/media/tv` |

Media mounts are read-only. Jellyfin has no write access to the media directories.

## Networking

Uses `network_mode: host` for local network discovery (DLNA broadcast).

## First run

```bash
# Create directories
sudo mkdir -p /opt/appdata/jellyfin/{config,cache}
sudo mkdir -p /mnt/media/{movies,tv}

# Start
docker compose up -d

# Logs
docker compose logs -f jellyfin
```

