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

### 1. Log in

Recent versions of the linuxserver image generate a random password on first
run. Retrieve it from the logs before attempting to log in — using the wrong
password multiple times will trigger an IP ban, requiring a container restart
to clear.

```bash
docker compose logs qbittorrent | grep -i password
```

Log in at `http://kostyan-server.salmon-halfmoon.ts.net:8080` with username
`admin` and the password from the logs.

### 2. Change the password

Settings → Web UI → Authentication → set a new username and password → Save.

### 3. Whitelist Tailscale subnet

To skip authentication when accessing from any Tailscale node:

Settings → Web UI → Authentication → enable
"Bypass authentication for clients in whitelisted IP subnets" →
add `100.64.0.0/10` → Save.

### 4. Connect Radarr to qBittorrent

Radarr and Sonarr send torrents to qBittorrent over the `arr` Docker network,
so they reach it by container name rather than IP or Tailscale hostname.

In Radarr → Settings → Download Clients → Add → qBittorrent:
- Host: `qbittorrent` (container name, not an IP or external hostname)
- Port: `8080`
- Category: `radarr` (qBittorrent will use this to organise downloads into
  `/media/torrents/radarr` and make it easier to track which torrents belong
  to which service)
- Test → Save

### 5. Connect Sonarr to qBittorrent

Same as Radarr:
- Host: `qbittorrent`
- Port: `8080`
- Category: `sonarr`
- Test → Save

### 6. Configure remote path mapping in Radarr and Sonarr

qBittorrent reports completed download paths using its own internal container
paths. Radarr and Sonarr need to know how to translate those paths to their
own container paths, otherwise they cannot find the files to import.

In Radarr → Settings → Download Clients → Remote Path Mappings → Add:
- Host: `qbittorrent`
- Remote Path: `/downloads`
- Local Path: `/media/torrents`

Repeat in Sonarr with the same values.

### 7. Configure save paths

In qBittorrent → Settings → Downloads:
- Default Save Path: `/media/torrents`

Then set up per-category paths so Radarr and Sonarr downloads land in separate
subdirectories. In the left sidebar, right click Categories → Add Category:

- Name: `radarr`, Save Path: `/media/torrents/radarr`
- Name: `sonarr`, Save Path: `/media/torrents/sonarr`