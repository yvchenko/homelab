# qBittorrent

Torrent client. Runs on `kostyan-server`.

## Access

| Interface | URL |
|-----------|-----|
| Web UI | http://kostyan-server.salmon-halfmoon.ts.net:8080 |

Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image |
|-----------|-------|
| Torrent client | `lscr.io/linuxserver/qbittorrent:latest` |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Config | `/opt/appdata/qbittorrent` | `/config` |
| Downloads | `/mnt/media/torrents` | `/media/torrents` |

## Networking

Joins the existing `arr` bridge network so Radarr and Sonarr can reach it at
`http://qbittorrent:8080`. Port 6881 (TCP/UDP) is the torrent peer port.


## First run

```bash
# Create config directory
sudo mkdir -p /opt/appdata/qbittorrent

# Start
docker compose up -d

# Logs
docker compose logs -f qbittorrent
```

## Post-startup configuration

1. Log in with default credentials (`admin` / `adminadmin`) and change the password immediately
2. In Radarr: Settings → Download Clients → Add → qBittorrent → `http://qbittorrent:8080`
3. In Sonarr: same as above
4. Set download category in Radarr/Sonarr to match qBittorrent category for automated management