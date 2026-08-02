# Media Download

Media acquisition, indexing, and request-management stack. Runs on both
`kostyan-server` and `nat-server` simultaneously (separate independent
instances, not shared) — each node has its own arr stack and qBittorrent,
downloading to its own local media library. Accessible over Tailscale only.

Prowlarr's UI quirks and setup notes live separately in `ACQUISITION.md` in this folder.

## Stack

| Component | Image | k8s primitive | Purpose |
|---|---|---|---|
| Radarr | `lscr.io/linuxserver/radarr:latest` | DaemonSet | Movie library management |
| Sonarr | `lscr.io/linuxserver/sonarr:latest` | DaemonSet | TV library management |
| Prowlarr | `lscr.io/linuxserver/prowlarr:latest` | DaemonSet | Indexer management |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr:latest` | DaemonSet | Cloudflare/anti-bot bypass proxy — used by Prowlarr (indexers) and Suwayomi (manga sources, `reading-library/`) |
| qBittorrent | `lscr.io/linuxserver/qbittorrent:latest` | DaemonSet | Torrent client |
| Dante | `yvchenko/dante-proxy:latest` (custom, pushed to Docker Hub) | Deployment | SOCKS5 proxy — routes nat-server's qBittorrent peer traffic through kostyan-server's IP |

All namespaced under `media-download`. Radarr, Sonarr, Prowlarr, FlareSolverr,
and qBittorrent are each a **DaemonSet** — one pod per labeled node, from a
single manifest, rather than a Deployment. Dante is a plain **Deployment**,
since it only ever runs on kostyan-server.

Node labels used:
```bash
sudo k3s kubectl label node nat-server arr-stack=true qbittorrent=true
sudo k3s kubectl label node gwserver arr-stack=true qbittorrent=true
```
(Dante uses the existing `disk: kostyan-media` label, no separate label
needed since it's single-node.)

**Why DaemonSet, not a Deployment with `replicas: 2`?** Each node's instance
needs its own node's local `/mnt/media` and `/opt/appdata/*` — Deployment
replicas are meant to be interchangeable and could, in principle, both land
on the same node, which would port-conflict since these all run with
`hostNetwork: true`. A DaemonSet guarantees exactly one pod per matching
node, which is what "two independent instances" actually requires here.

## Paths

| Purpose | Host path | Container path |
|---|---|---|
| Radarr config | `/opt/appdata/radarr` | `/config` |
| Sonarr config | `/opt/appdata/sonarr` | `/config` |
| Prowlarr config | `/opt/appdata/prowlarr` | `/config` |
| qBittorrent config | `/opt/appdata/qbittorrent` | `/config` |
| Media (all arr services + qBittorrent) | `/mnt/media` | `/media` |
| Dante build/config | `services/media-download/dante/` | — |

All mounted via `hostPath`. Same single shared `/mnt/media:/media` mount as
before — no separate torrents mount, hardlinking behavior unchanged.

## Networking

**Everything in this stack runs with `hostNetwork: true`**. Radarr, Sonarr, Prowlarr,
FlareSolverr, qBittorrent, and Dante all share the real host network
namespace directly.

**FlareSolverr, reached via `http://localhost:8191`, not container name.**
Since everything's on the real host network now, `http://flaresolverr:8191`
(container-name DNS) no longer resolves — this is a genuine one-time manual
change needed in Prowlarr's indexer-proxy settings after cutover, not
something the manifest can carry over automatically. **qBittorrent** is likewise 
reachable at `http://localhost:8080`.

### DNS — the biggest gotcha in the stack

`hostNetwork: true` pods do **not** reliably resolve DNS by default, for
either Tailscale MagicDNS names (`*.salmon-halfmoon.ts.net`) or ordinary
internet domains. Every service in this stack that talks to anything by
hostname needs this exact fix in its manifest:

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 100.100.100.100   # Tailscale's own resolver, for MagicDNS names
    - 1.1.1.1            # public fallback, for everything else
    - 1.0.0.1
  searches:
    - salmon-halfmoon.ts.net
```

Two "obvious" alternatives were tried first and **both failed**:

- `dnsPolicy: ClusterFirstWithHostNet` (the setting Kubernetes' own docs
  recommend for exactly this scenario) — the pod's `/etc/resolv.conf` still
  pointed at CoreDNS, which doesn't reliably forward Tailscale MagicDNS
  lookups.
- `dnsPolicy: Default` (use the node's own resolv.conf) — Tailscale's
  MagicDNS integration works via split-DNS *inside systemd-resolved
  itself*, not the flat `/etc/resolv.conf` file. `Default` just copies that
  flat file, which shows only the generic ISP upstream, with no awareness
  of the `.ts.net` special case.

Only explicit `dnsPolicy: None` + a manually specified `dnsConfig` actually
worked.

**One more trap inside that fix**: the first attempt used nat-server's own
ISP resolver IPs as the fallback instead of a public one. Since these are
DaemonSets running on *both* nodes, gwserver's pods were also told to use
nat-server's ISP resolver — many ISP recursive resolvers reject queries
from outside their own subscriber range, silently breaking general (non-
`.ts.net`) DNS resolution specifically on gwserver. **Use a genuinely
public resolver (`1.1.1.1`/`1.0.0.1`) as the fallback, never a specific
node's own ISP resolver, in any manifest shared across both nodes.**

## Service relationships

- Radarr / Sonarr → Prowlarr (indexer lookups)
- Radarr / Sonarr → qBittorrent, via Tailscale hostname (send downloads)
- Prowlarr → FlareSolverr, via `localhost:8191` (Cloudflare/anti-bot bypass)
- Suwayomi (`reading-library/`) → FlareSolverr, also via
  `localhost:8191`, reusing this stack's per-node instance rather than a
  cross-namespace Service reference

## First run

```bash
# Create config directories
sudo mkdir -p /opt/appdata/{radarr,sonarr,prowlarr,qbittorrent}

# Fix ownership so containers can write to media directories
sudo chown -R 1000:1000 /mnt/media

sudo k3s kubectl create namespace media-download
sudo k3s kubectl label node nat-server arr-stack=true qbittorrent=true
sudo k3s kubectl label node gwserver arr-stack=true qbittorrent=true

sudo k3s kubectl apply -f services/media-download/dante/manifest.yaml
sudo k3s kubectl apply -f services/media-download/qbittorrent/manifest.yaml
sudo k3s kubectl apply -f services/media-download/arr-stack/manifest.yaml
sudo k3s kubectl get pods -n media-download -o wide

# Logs
sudo k3s kubectl logs -n media-download <pod-name> -f
```

**Migrating a live instance off Docker?** Stop the old container(s) on each
node *before* applying the matching k8s manifest.

```bash
docker stop dante-proxy qbittorrent radarr sonarr prowlarr flaresolverr
```

## Post-startup configuration

Order matters: Prowlarr → Radarr/Sonarr → qBittorrent connection → Dante
(if this node's qBittorrent needs to proxy through the other node).

### 1. Prowlarr — add indexers

See `PROWLARR.md` for indexer-specific quirks.

1. Prowlarr → Indexers → Add Indexer, fill in credentials, Test → Save
2. Add Radarr and Sonarr via Prowlarr → Apps → Add App
3. For Cloudflare/anti-bot indexer errors: Settings → Indexers →
   FlareSolverr, add proxy `http://localhost:8191`, tag the failing
   indexer to use it

### 2. Radarr / Sonarr — root folders and download client

1. Settings → Media Management → Root Folders → Add:
   - Radarr: `/media/movies`
   - Sonarr: `/media/tv`
2. Settings → Download Clients → Add → qBittorrent:
   - Host: `localhost`
   - Port: `8080`
   - Category: `radarr` / `sonarr` respectively
   - Test → Save

### 3. qBittorrent — first login and security

Recent linuxserver images generate a random password on first run.

```bash
sudo k3s kubectl logs -n media-download <qbittorrent-pod-name> | grep -i password
```

Log in at `http://<node>.salmon-halfmoon.ts.net:8080`, username `admin`.

> ⚠️ Wrong password attempts trigger an IP ban requiring a pod restart to
> clear (`kubectl delete pod <qbittorrent-pod-name> -n media-download`).

1. Settings → Web UI → Authentication → set new username/password → Save
2. Whitelist the Tailscale subnet to skip auth from any tailnet node:
   enable "Bypass authentication for clients in whitelisted IP subnets" →
   add `100.64.0.0/10` → Save
3. Settings → Downloads → Default Save Path: `/media/torrents`
4. Add categories with per-category save paths:
   - `radarr` → `/media/torrents/radarr`
   - `sonarr` → `/media/torrents/sonarr`

### 4. Port forwarding (peer connections)

Forward port 6881 (TCP/UDP) on the router to the host machine. Without this,
torrents stall even when trackers are reachable. Verify externally at
https://canyouseeme.org.

### 5. Dante (nat-server's qBittorrent only)

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

**Custom image, built and pushed manually** — no CI, no auto-rebuild:
```bash
docker build --build-arg DANTE_VERSION=1.4.3+dfsg-1 -t yvchenko/dante-proxy:latest ./dante
docker push yvchenko/dante-proxy:latest
```
Repo is currently **public** on Docker Hub, deliberately deferred making it private 
until a proper Secrets Manager setup exists for the eventual `imagePullSecret`.

`danted.conf` is baked into the image via `COPY` (not a ConfigMap) — config
is stable, baking it in is simpler than managing a separate object for it.
Config tweaks require an image rebuild + push, not just a restart. Since
k8s PodSpecs have no equivalent to Compose's `ulimits:` block, the fd-limit
fix is baked into the image's start command instead:

```dockerfile
CMD ["sh", "-c", "ulimit -n 65536 && exec danted -f /etc/danted.conf"]
```

Confirm `DANTE_VERSION` is still current for Ubuntu 24.04 before a rebuild:
```bash
docker run --rm ubuntu:24.04 bash -c "apt-get update && apt-cache madison dante-server"
```

Confirm it's bound to the tailnet only, not `0.0.0.0`, once deployed:
```bash
sudo k3s kubectl exec -n media-download <dante-pod-name> -- ss -tlnp | grep 1080
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

- **DNS is the big one — see the dedicated section above.** Every
  `hostNetwork` pod in this stack needs the explicit `dnsPolicy: None` +
  `dnsConfig` fix; neither of Kubernetes' two "recommended" alternatives
  actually works for Tailscale MagicDNS resolution.
- **A leftover Docker container will win a port race against its k8s
  replacement.** Always `docker stop` the old container for a service
  before applying its k8s manifest — recurred for every single service in
  this cluster during cutover.
- **Prowlarr's `net.ipv6.conf.all.disable_ipv6` sysctl had to be dropped
  entirely**, not translated — Kubernetes flatly disallows any
  network-namespace-scoped sysctl override when `hostNetwork: true` is set
  (the pod has no network namespace of its own to apply it to). In
  practice this turned out fine without it — the sysctl was only ever
  affecting Prowlarr's own bridge-network namespace under Compose, which
  doesn't exist anymore now that it's on the real host network.
- **The custom Prowlarr indexer definition (`audiobookbay.yml`, see
  `audiobooks/README.md`) is a `hostPath` file mount pointing at a path
  inside the git checkout itself, not `/opt/appdata/`.** If gwserver's repo
  checkout is stale (behind a `git pull`) when Prowlarr's pod is
  (re)scheduled there, the pod fails outright — `hostPath type check
  failed: ... is not a file` — rather than silently starting without the
  custom indexer. Make sure both nodes' checkouts are current before
  touching this manifest.
- **DHT cannot be tunneled through SOCKS5** — libtorrent doesn't support
  it; qBittorrent's "disable connections not supported by proxies" just
  turns DHT off rather than routing it. DHT is disabled on nat-server by
  design; peer discovery relies on trackers + PeX. kostyan-server's
  qBittorrent keeps DHT on since it doesn't proxy.
- **A handful of specific indexers return `429 Too Many Requests`
  consistently on nat-server and gwserver**, for the same indexer,
  tested back-to-back. Confirmed *not* a connectivity/DNS problem — the
  request reaches the indexer and gets a real HTTP response — and doesn't
  clear with time. **Not investigated further, pinned as a known,
  non-blocking loose end** — don't mistake it for a fresh regression later.
- On nat-server specifically (a busier host with more going on
  concurrently), qBittorrent's TCP listener has occasionally failed to
  bind on a single startup attempt, showing only the UDP/µTP success line
  in its logs with no TCP line. A pod recreation
  (`kubectl delete pod <name> -n media-download`) a few seconds later has
  bound cleanly every time observed so far. Not yet a confirmed root
  cause — noted here in case it recurs.
- **Before assuming a "0 peers, DHT: 0 nodes" symptom is a fresh
  regression, check for leftover backgrounded test processes squatting on
  the host port** (`sudo lsof -i :6881`) — a stray `nc` or similar left
  running from an earlier debugging session on the *host* will silently
  block the real qBittorrent pod's TCP listener from binding, and looks
  identical to a genuine config/DNS problem.
