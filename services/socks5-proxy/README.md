# socks5-proxy

Lightweight SOCKS5 proxy running on Kostyan's server. Used to route qBittorrent traffic on the Spain node through the Ukrainian IP over Tailscale.

## Stack

| Component | Image                      |
|-----------|----------------------------|
| Proxy     | `serjs/go-socks5-proxy`    |

## Paths

| Purpose       | Path                                      |
|---------------|-------------------------------------------|
| Compose file  | `/opt/gitops/services/socks5-proxy/`      |

No persistent data — stateless service, nothing to mount.

## First run

```bash
docker compose up -d
```

## Post-startup: configure qBittorrent

In qBittorrent on the Spain node: **Tools → Options → Connection → Proxy Server**

| Setting       | Value                                        |
|---------------|----------------------------------------------|
| Type          | SOCKS5                                       |
| Host          | `kostyan-server.salmon-halfmoon.ts.net`      |
| Port          | `1080`                                       |
| Authentication | Disabled (unless env vars are uncommented)  |

Enable **"Use proxy for peer connections"** and optionally **"Disable connections not supported by proxies"** to avoid any traffic leaking outside the proxy.

## Auth (optional)

Unauthenticated by default — access is Tailscale-gated. To add credentials, add an `environment` block in `docker-compose.yml` and set `PROXY_USER` / `PROXY_PASSWORD` in a `.env` file alongside it.