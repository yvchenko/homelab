# Dante SOCKS5 Proxy

SOCKS5 proxy running on kostyan-server (gwserver), used to route qBittorrent's
peer traffic from nat-server through kostyan-server's IP. Replaces the old
`serjs/go-socks5-proxy` container, which didn't support UDP and broke DHT.

## Access

| What | Value |
|---|---|
| Host | `kostyan-server.salmon-halfmoon.ts.net` |
| Port | `1080` |
| Type | SOCKS5, no auth |
| Scope | Tailscale tailnet only (`100.64.0.0/10`) — not reachable from LAN or public internet |

## Stack

| Component | Details |
|---|---|
| Image | Built locally from Ubuntu 24.04, package `dante-server` |
| Container | `dante-proxy` |
| Network | `network_mode: host` — binds directly to `tailscale0`, required for UDP ASSOCIATE to work properly |
| Internal interface | `tailscale0` |
| External interface | `enp2s0` |

## Paths

| Path | Purpose |
|---|---|
| `~/homelab/services/dante/Dockerfile` | Image build, installs pinned `dante-server` version |
| `~/homelab/services/dante/danted.conf` | Dante config — interfaces, access rules |
| `~/homelab/services/dante/docker-compose.yml` | Compose service definition |
| `~/homelab/services/dante/.env` | `DANTE_VERSION` pin — not committed |

## First-run setup

```bash
echo "DANTE_VERSION=1.4.3+dfsg-1" > .env
docker compose up -d --build
```

Confirm `DANTE_VERSION` is still current for Ubuntu 24.04 before a future rebuild:
```bash
docker run --rm ubuntu:24.04 bash -c "apt-get update && apt-cache madison dante-server"
```

## Post-startup checks

Confirm it's bound to the tailnet only, not `0.0.0.0`:
```bash
ss -tlnp | grep 1080
```

Test the proxy from another tailnet node (e.g. nat-server):
```bash
curl -x socks5h://kostyan-server.salmon-halfmoon.ts.net:1080 https://ifconfig.me
```
Should return kostyan-server's public IP, not the calling node's.

## qBittorrent client config (nat-server)

Settings → Connection → Proxy Server:
- Type: SOCKS5
- Host: `kostyan-server.salmon-halfmoon.ts.net`, Port: `1080`
- Use proxy for BitTorrent purposes / peer connections: enabled
- Perform hostname lookup via proxy: enabled

## Known limitation: DHT

libtorrent does not support tunneling DHT traffic through a SOCKS5 proxy —
the "use proxy" settings only cover peer connections and (partially) UDP
trackers, never DHT. The only DHT-related option qBittorrent exposes
("Disable connections not supported by proxies") simply turns DHT off
entirely rather than routing it.

DHT is disabled here by design, to avoid leaking nat-server's identity via
unproxied DHT announcements. Peer discovery relies on trackers and PeX
instead, which is sufficient in practice.

## Notes

- `ulimits.nofile` is set to 65536 in the compose file — the container's
  default fd limit was too low and caused intermittent
  `sending client to io-child... Resource temporarily unavailable` errors
  under torrent connection load.
- `danted.conf` is also bind-mounted at runtime (not just baked into the
  image) so config tweaks don't require a rebuild.