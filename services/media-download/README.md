# Media Download

Media acquisition, indexing, and request-management stack. Runs on both
`kostyan-server` and `nat-server` simultaneously (separate independent
instances, not shared) — each node has its own arr stack and qBittorrent,
downloading to its own local media library. Accessible over Tailscale only.

Prowlarr's UI quirks and setup notes live separately in `PROWLARR.md` at this
folder's root, since it's the shared search/indexing layer for the whole
media pipeline (video, and manga acquisition via nyaa.si), not arr-specific.

## Stack

| Component | Image | Purpose |
|---|---|---|
| Radarr | `lscr.io/linuxserver/radarr:latest` | Movie library management |
| Sonarr | `lscr.io/linuxserver/sonarr:latest` | TV library management |
| Prowlarr | `lscr.io/linuxserver/prowlarr:latest` | Indexer management |
| Bazarr | `lscr.io/linuxserver/bazarr:latest` | Subtitle management |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr:latest` | Cloudflare/anti-bot bypass proxy — used by Prowlarr (indexers) and Suwayomi (manga sources, separate stack) |
| qBittorrent | `lscr.io/linuxserver/qbittorrent:latest` | Torrent client |
| Dante | built locally, Ubuntu 24.04 + `dante-server` | SOCKS5 proxy — routes nat-server's qBittorrent peer traffic through kostyan-server's IP |

## Paths

| Purpose | Host path | Container path |
|---|---|---|
| Radarr config | `/opt/appdata/radarr` | `/config` |
| Sonarr config | `/opt/appdata/sonarr` | `/config` |
| Prowlarr config | `/opt/appdata/prowlarr` | `/config` |
| Bazarr config | `/opt/appdata/bazarr` | `/config` |
| qBittorrent config | `/opt/appdata/qbittorrent` | `/config` |
| Media (all arr services + qBittorrent) | `/mnt/media` | `/media` |
| Dante build/config | `services/media-download/dante/` | — |

All arr services and qBittorrent share one `/mnt/media:/media` mount — there
is no separate `/mnt/media/torrents` mount. Torrents land in
`/mnt/media/torrents/` as a plain subdirectory of the shared mount, which is
what enables Radarr/Sonarr to hardlink completed downloads into
`/media/movies` / `/media/tv` instead of copying. (Earlier docs described a
dedicated torrents-only mount for qBittorrent — that was never actually the
case; this is the corrected version.)

## Networking

Radarr, Sonarr, Prowlarr, Bazarr, and FlareSolverr share the `media_download`
bridge network and reach each other by container name (e.g.
`http://flaresolverr:8191`). Suwayomi (separate stack, `reading-library/`)
joins this network externally to reach FlareSolverr too.

**qBittorrent and Dante are not on this network** — both use
`network_mode: host`, which Compose doesn't allow combining with `networks:`.
This means:

- **Radarr/Sonarr do not reach qBittorrent by container name.** The real,
  working config uses qBittorrent's **Tailscale hostname**
  (`<node>.salmon-halfmoon.ts.net`) and port `8080`, same as any other
  Tailscale-reachable service. `http://qbittorrent:8080` will not resolve —
  ignore any docs or instructions that say otherwise.
- Since qBittorrent and Radarr/Sonarr mount the identical host path
  (`/mnt/media`), remote path mappings between them are likely unnecessary
  in practice — container-internal `/media/torrents` already matches on both
  sides. If you have a remote path mapping configured anyway, verify it's
  actually a no-op (`Remote Path` = `Local Path`) rather than assuming it's
  required; the previous docs described one but that was written against
  the never-implemented bridge-network design.

## Service relationships

- Radarr / Sonarr → Prowlarr (indexer lookups)
- Radarr / Sonarr → qBittorrent, via Tailscale hostname (send downloads)
- Bazarr → Radarr / Sonarr (library sync + subtitle management)
- Prowlarr → FlareSolverr (Cloudflare/anti-bot bypass for indexers)
- Suwayomi (external stack) → FlareSolverr (same bypass, manga sources)

## First run

```bash
# Create config directories
sudo mkdir -p /opt/appdata/{radarr,sonarr,prowlarr,bazarr,qbittorrent}

# Fix ownership so containers can write to media directories
sudo chown -R 1000:1000 /mnt/media

# Dante needs its version pin — see dante/.env.example
cp dante/.env.example .env
# edit DANTE_VERSION

# Start everything
docker compose up -d --build

# Logs
docker compose logs -f
```

## Post-startup configuration

Order matters: Prowlarr → Radarr/Sonarr → Bazarr/FlareSolverr → qBittorrent
connection → Dante (if this node's qBittorrent needs to proxy through the
other node).

### 1. Prowlarr — add indexers

See `PROWLARR.md` for indexer-specific quirks.

1. Prowlarr → Indexers → Add Indexer, fill in credentials, Test → Save
2. Add Radarr and Sonarr via Prowlarr → Apps → Add App
3. For Cloudflare/anti-bot indexer errors: Settings → Indexers →
   FlareSolverr, add proxy `http://flaresolverr:8191`, tag the failing
   indexer to use it

### 2. Radarr / Sonarr — root folders and download client

1. Settings → Media Management → Root Folders → Add:
   - Radarr: `/media/movies`
   - Sonarr: `/media/tv`
2. Settings → Download Clients → Add → qBittorrent:
   - **Host: the node's Tailscale hostname** (e.g.
     `kostyan-server.salmon-halfmoon.ts.net`), not `qbittorrent`
   - Port: `8080`
   - Category: `radarr` / `sonarr` respectively
   - Test → Save

### 3. Bazarr — connect to Radarr and Sonarr

1. Settings → Radarr: Host `radarr`, Port `7878`, API key from Radarr →
   Settings → General, Test → Save
2. Settings → Sonarr: Host `sonarr`, Port `8989`, API key from Sonarr →
   Settings → General, Test → Save
3. Configure subtitle providers (Settings → Providers) and languages
4. Trigger a full library scan if existing media is present

### 4. qBittorrent — first login and security

Recent linuxserver images generate a random password on first run.

```bash
docker compose logs qbittorrent | grep -i password
```

Log in at `http://<node>.salmon-halfmoon.ts.net:8080`, username `admin`.

> ⚠️ Wrong password attempts trigger an IP ban requiring a container restart
> to clear.

1. Settings → Web UI → Authentication → set new username/password → Save
2. Whitelist the Tailscale subnet to skip auth from any tailnet node:
   enable "Bypass authentication for clients in whitelisted IP subnets" →
   add `100.64.0.0/10` → Save
3. Settings → Downloads → Default Save Path: `/media/torrents`
4. Add categories with per-category save paths:
   - `radarr` → `/media/torrents/radarr`
   - `sonarr` → `/media/torrents/sonarr`

### 5. Port forwarding (peer connections)

Forward port 6881 (TCP/UDP) on the router to the host machine. Without this,
torrents stall even when trackers are reachable. Verify externally at
https://canyouseeme.org.

### 6. Dante (nat-server's qBittorrent only)

nat-server's qBittorrent routes peer traffic through kostyan-server's Dante
instance to avoid exposing nat-server's IP via unproxied DHT. kostyan-server's
own qBittorrent does **not** use Dante — it stays on its native Ukrainian IP
by design.

**Access**

| What | Value |
|---|---|
| Host | `kostyan-server.salmon-halfmoon.ts.net` |
| Port | `1080` |
| Type | SOCKS5, no auth |
| Scope | Tailscale tailnet only (`100.64.0.0/10`) |

**Setup**

```bash
docker compose up -d --build dante
```

Confirm `DANTE_VERSION` (in `.env`) is still current for Ubuntu 24.04 before
a rebuild:

```bash
docker run --rm ubuntu:24.04 bash -c "apt-get update && apt-cache madison dante-server"
```

Confirm it's bound to the tailnet only, not `0.0.0.0`:

```bash
ss -tlnp | grep 1080
```

Test from another tailnet node:

```bash
curl -x socks5h://kostyan-server.salmon-halfmoon.ts.net:1080 https://ifconfig.me
# should return kostyan-server's public IP, not the caller's
```

**qBittorrent config (nat-server only)** — Settings → Connection → Proxy
Server:
- Type: SOCKS5
- Host: `kostyan-server.salmon-halfmoon.ts.net`, Port: `1080`
- Use proxy for peer connections: enabled
- Perform hostname lookup via proxy: enabled

## Known gotchas

- **qBittorrent and Dante use `network_mode: host`** — neither is reachable
  by container name from anything on `media_download`. Radarr/Sonarr must
  use qBittorrent's Tailscale hostname, never `qbittorrent`.
- **DHT cannot be tunneled through SOCKS5** — libtorrent doesn't support it;
  qBittorrent's "disable connections not supported by proxies" just turns
  DHT off rather than routing it. DHT is disabled on nat-server by design;
  peer discovery relies on trackers + PeX. kostyan-server's qBittorrent
  keeps DHT on since it doesn't proxy.
- **Dante `ulimits.nofile: 65536`** — the container default fd limit caused
  intermittent `sending client to io-child... Resource temporarily
  unavailable` errors under load.
- **`danted.conf` is bind-mounted, not baked into the image** — config
  tweaks don't require a rebuild, just a restart.
- **`DANTE_VERSION` build arg requires `.env`** at `media-download/` root
  (not nested in `dante/`) — Compose reads `.env` from the same directory as
  the compose file by default.
- **Startup order**: `reading-library/` depends on this stack's
  `media_download` network existing for Suwayomi → FlareSolverr. Bring this
  stack up first.