# Arr Stack

Media acquisition and request management services. Runs on Kostya's node
(`kostyan-server`) and on Nat's node (`nat-server`) simultaneously. 
Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image | Purpose |
|-----------|-------|---------|
| Radarr | `lscr.io/linuxserver/radarr:latest` | Movie library management |
| Sonarr | `lscr.io/linuxserver/sonarr:latest` | TV library management |
| Prowlarr | `lscr.io/linuxserver/prowlarr:latest` | Indexer management |
| Bazarr | `lscr.io/linuxserver/bazarr:latest` | Subtitle management |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr:latest` | Proxy for bypassing Cloudflare/anti-bot challenges — used by Prowlarr (indexers) and Suwayomi (manga sources) |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Radarr config | `/opt/appdata/radarr` | `/config` |
| Sonarr config | `/opt/appdata/sonarr` | `/config` |
| Prowlarr config | `/opt/appdata/prowlarr` | `/config` |
| Bazarr config | `/opt/appdata/bazarr` | `/config` |
| Media | `/mnt/media` | `/media` |

All arr services share a unified `/mnt/media` mount to enable hardlinks when
Radarr/Sonarr move completed downloads from `/media/torrents` into
`/media/movies` and `/media/tv`.

Bazarr scans the same media library to automatically download and manage
subtitles for movies and TV shows.

## Networking

Services communicate over the `arr` bridge network. АlareSolverr is reachable by 
container name (`http://flaresolverr:8191`) from anything else on the `arr` network 
— used by Prowlarr for indexers that require Cloudflare/anti-bot bypass, and by 
Suwayomi (separate stack, joins this network externally) for manga sources with 
the same protection. Note: Docker Compose project-name prefixing means the actual network 
name is `arr_arr`, not `arr` — external stacks referencing it need `name: arr_arr`.

## Service relationships

- Radarr / Sonarr → Prowlarr     (indexer lookups)
- Radarr / Sonarr → qBittorrent  (send downloads)  ← configured after qbittorrent setup
- Bazarr → Radarr / Sonarr       (library sync + subtitle management)

## First run

```bash
# Create config directories
sudo mkdir -p /opt/appdata/{radarr,sonarr,prowlarr,bazarr}

# Fix ownership so containers can write to media directories
sudo chown -R 1000:1000 /mnt/media

# Start
docker compose up -d

# Logs
docker compose logs -f
```

## Post-startup configuration

Follow this order — Prowlarr must be configured before Radarr/Sonarr, and
both must be configured before Bazarr and Flaresolverr.

### 1. Prowlarr — add indexers

Indexers are the sources Prowlarr searches for torrents. Radarr and Sonarr
do not search indexers directly — they go through Prowlarr.

1. Go to Prowlarr → Indexers → Add Indexer
2. Browse the catalogue or search by name
3. Select an indexer and fill in any required credentials (public indexers
   need none; private trackers require a passkey or cookie from your account)
4. Click Test — if it passes, Save
5. Repeat for additional indexers
6. Add Radarr and Sonarr via Prowlarr → Apps → Add App
7. For indexers that fail with a Cloudflare/anti-bot error, go to
   Settings → Indexers → FlareSolverr, add a proxy with host
   `http://flaresolverr:8191`, then edit the failing indexer and select it
   under Tags/FlareSolverr

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

### 4. Bazarr — connect to Radarr and Sonarr

Bazarr manages subtitle downloads and synchronization for existing media.

1. Open Bazarr
2. Settings → Radarr
   - Host: `radarr`
   - Port: `7878`
   - API key: from Radarr → Settings → General
   - Base URL: leave empty
   - Test and Save
3. Settings → Sonarr
   - Host: `sonarr`
   - Port: `8989`
   - API key: from Sonarr → Settings → General
   - Base URL: leave empty
   - Test and Save
4. Configure subtitle providers under Settings → Providers
5. Configure desired languages under Settings → Languages
6. Trigger a full library scan if existing media is already present