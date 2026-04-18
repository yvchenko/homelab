# Arr Stack

Media acquisition and request management services. Runs on Kostyan's node
(`kostyan-server`).

## Access

| Service | URL |
|---------|-----|
| Radarr | http://kostyan-server.salmon-halfmoon.ts.net:7878 |
| Sonarr | http://kostyan-server.salmon-halfmoon.ts.net:8989 |
| Prowlarr | http://kostyan-server.salmon-halfmoon.ts.net:9696 |
| Jellyseerr | http://kostyan-server.salmon-halfmoon.ts.net:5055 |

Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image | Purpose |
|-----------|-------|---------|
| Radarr | `lscr.io/linuxserver/radarr:latest` | Movie library management |
| Sonarr | `lscr.io/linuxserver/sonarr:latest` | TV library management |
| Prowlarr | `lscr.io/linuxserver/prowlarr:latest` | Indexer management |
| Jellyseerr | `fallenbagel/jellyseerr:latest` | Request management |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Radarr config | `/opt/appdata/radarr` | `/config` |
| Sonarr config | `/opt/appdata/sonarr` | `/config` |
| Prowlarr config | `/opt/appdata/prowlarr` | `/config` |
| Jellyseerr config | `/opt/appdata/jellyseerr` | `/app/config` |
| Media | `/mnt/media` | `/media` |

All arr services share a unified `/mnt/media` mount to enable hardlinks when
Radarr/Sonarr move completed downloads from `/media/torrents` into
`/media/movies` and `/media/tv`.

## Networking

Services communicate over the `arr` bridge network. Jellyseerr reaches Jellyfin
via the Tailscale hostname since Jellyfin runs on host network mode.

## Service relationships

- Jellyseerr → Radarr / Sonarr   (send requests)
- Radarr / Sonarr → Prowlarr     (indexer lookups)
- Radarr / Sonarr → qBittorrent  (send downloads)  ← configured after qbittorrent setup

## First run

```bash
# Create config directories
sudo mkdir -p /opt/appdata/{radarr,sonarr,prowlarr,jellyseerr}

# Start
docker compose up -d

# Logs
docker compose logs -f
```

## Post-startup configuration

1. **Prowlarr** — add indexers first
2. **Radarr/Sonarr** — connect to Prowlarr, then to qBittorrent (after that stack is up)
3. **Jellyseerr** — connect to Jellyfin at `http://kostyan-server.salmon-halfmoon.ts.net:8096`,
   then to Radarr and Sonarr