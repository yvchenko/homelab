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

# Fix ownership so containers can write to media directories
sudo chown -R 1000:1000 /mnt/media

# Start
docker compose up -d

# Logs
docker compose logs -f
```

## Post-startup configuration

## Post-startup configuration

Follow this order — Prowlarr must be configured before Radarr/Sonarr, and
both must be configured before Jellyseerr.

### 1. Prowlarr — add indexers

Indexers are the sources Prowlarr searches for torrents. Radarr and Sonarr
do not search indexers directly — they go through Prowlarr.

1. Go to Prowlarr → Indexers → Add Indexer
2. Browse the catalogue or search by name
3. Select an indexer and fill in any required credentials (public indexers
   need none; private trackers require a passkey or cookie from your account)
4. Click Test — if it passes, Save
5. Repeat for additional indexers
6. Prowlarr will sync the indexers to Radarr and Sonarr automatically

### 2. Radarr — connect to Prowlarr and set root folder

1. Settings → Download Clients → Add → qBittorrent
   - Host: `qbittorrent`
   - Port: `8080`
   - Category: `radarr`
   - Test and Save
2. Settings → Media Management → Root Folders → Add Root Folder
   - Path: `/media/movies`
3. Prowlarr sync happens automatically — verify under Settings → Indexers

### 3. Sonarr — connect to Prowlarr and set root folder

Same as Radarr:
1. Settings → Download Clients → Add → qBittorrent
   - Host: `qbittorrent`
   - Port: `8080`
   - Category: `sonarr`
   - Test and Save
2. Settings → Media Management → Root Folders → Add Root Folder
   - Path: `/media/tv`

### 4. Jellyseerr — connect to Jellyfin, Radarr, and Sonarr

Jellyseerr setup runs as a wizard on first launch.

**Step 1 — Connect to Jellyfin:**
- Jellyfin URL: `http://kostyan-server.salmon-halfmoon.ts.net:8096`
- Enter your Jellyfin admin credentials
- Leave URL Base empty (only needed behind a reverse proxy)
- Sign in and proceed

**Step 2 — Connect to Radarr:**
- Server name: anything descriptive
- Host: `radarr`
- Port: `7878`
- API key: found in Radarr → Settings → General
- Test and proceed
- Root folder will populate from Radarr — select `/media/movies`
- Set quality profile to match what you configured in Radarr

**Step 3 — Connect to Sonarr:**
- Same as Radarr but:
- Host: `sonarr`
- Port: `8989`
- API key: from Sonarr → Settings → General
- Root folder: `/media/tv`