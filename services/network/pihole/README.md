# Pi-hole

Tailnet-wide DNS filtering. Single instance on nat-server, serving every device
on the tailnet via Tailscale global nameservers.

## Access

| What | Where |
|---|---|
| Web UI | http://100.83.164.52:8053/admin |
| DNS | 100.83.164.52:53 (bound to `tailscale0` only) |

## Stack

| Component | Detail |
|---|---|
| Image | `pihole/pihole:2026.05.0` (pinned — stateful, no `:latest`) |
| Namespace | `network` |
| Node | nat-server (control plane; kostyan-server has DTEK outages) |
| Networking | `hostNetwork: true`, `dns.listeningMode=BIND` on `tailscale0` |
| Upstreams | 1.1.1.1 ; 1.0.0.1 ; 9.9.9.9 |
| Web port | 8053 (8080 occupied, 8081 is Filebrowser) |

## Paths

| Path | Contents |
|---|---|
| `/opt/appdata/pihole` | FTL config, gravity + query DBs (hostPath, node-pinned) |

## First run

```bash
sudo mkdir -p /opt/appdata/pihole
kubectl create namespace network
kubectl -n network create secret generic pihole-admin \
  --from-literal=password="$(openssl rand -base64 18)"
kubectl apply -f services/network/pihole/pihole.yaml
kubectl -n network rollout status deploy/pihole
```

Retrieve the generated password:

```bash
kubectl -n network get secret pihole-admin -o jsonpath='{.data.password}' | base64 -d; echo
```

To change it, update the secret and roll — `pihole setpassword` will not persist,
because `FTLCONF_webserver_api_password` is set from the environment and is
therefore read-only:

```bash
kubectl -n network delete secret pihole-admin
kubectl -n network create secret generic pihole-admin --from-literal=password='newpassword'
kubectl -n network rollout restart deploy/pihole
```

## Post-startup (Tailscale admin console)

1. DNS → Global nameservers → **Custom...** → `100.83.164.52`
2. Leave **Restrict to domain** empty — filling it makes this a split-DNS rule
   that only applies to that one domain
3. Enable **Override local DNS**
4. Keep MagicDNS enabled; `*.salmon-halfmoon.ts.net` is still resolved by
   Tailscale itself, only everything else goes to Pi-hole

Do not add a public resolver as a second global nameserver "for redundancy" —
Tailscale picks between them non-deterministically and blocking becomes a
coin flip.

Force the config push instead of waiting for the poll (per node):

```bash
sudo tailscale set --accept-dns=false && sudo tailscale set --accept-dns=true
```

## Verify

```bash
dig +short doubleclick.net                     # expect 0.0.0.0
dig +short google.com                          # expect a real IP
dig +short nat-server.salmon-halfmoon.ts.net   # MagicDNS must still work
```

Run on both nodes. The queries without `@100.83.164.52` are the meaningful
ones — they test the pushed Tailscale config, not just the resolver.

## Blocklists

Default is StevenBlack (~150k domains). Added on top:

| List | Purpose |
|---|---|
| `https://adaway.org/hosts.txt` | Mobile app ads |
| `https://v.firebog.net/hosts/Easyprivacy.txt` | Trackers (most likely source of false positives) |

After changing lists:

```bash
kubectl -n network exec deploy/pihole -- pihole -g
```

To find which list caught a domain that shouldn't have been blocked:

```bash
kubectl -n network exec deploy/pihole -- pihole -q broken-domain.com
```

Allowlist the single domain rather than dropping the whole list.

## Known gotchas

- `tailscale0` carries a **/32**. `dns.listeningMode=LOCAL` treats the local
  subnet as a single host and drops every peer query. `BIND` is required.
- `BIND` uses `interface=` + `bind-interfaces`, binding only the Tailscale
  address. This is what keeps `systemd-resolved`'s stub on `127.0.0.53` /
  `127.0.0.54` from colliding, and keeps Pi-hole off the Spanish LAN/WAN.
- Upstreams must never be `100.100.100.100` — that resolves back to Pi-hole.
- Pod needs `dnsPolicy: None` + explicit `dnsConfig`, or gravity list updates
  try to resolve through Pi-hole itself.
- FTL binds at start-up. If `tailscale0` is down when the pod starts it
  crashloops until restarted — expected signature after a node reboot.
- The web server loses bind races silently: DNS keeps working while the UI
  404s from whatever else holds the port. Check with `ss -tlpn | grep ':8053'`
  that the socket actually belongs to `pihole-FTL`.
- Settings passed as `FTLCONF_*` become **read-only** in the web UI. Blocklists,
  groups and allowlists are dashboard state in `/opt/appdata/pihole`, not in
  the manifest — they are not captured by GitOps.
- k3s CoreDNS forwards to the node resolver, so every pod in the cluster now
  resolves through Pi-hole. If Radarr/Prowlarr indexer lookups start failing
  after a blocklist change, check the Query Log before blaming the indexer.
- YouTube ads cannot be blocked at DNS level — they come from
  `googlevideo.com`, the same domain as the video stream. Not a valid test.
- `d3ward.github.io/toolz/adblock.html` is archived and no longer works.
  Use `https://canyoublockit.com/simple-test/` or just watch the Query Log.
- Browsers using DNS-over-HTTPS bypass Pi-hole entirely. If a device never
  appears in the Query Log, check its DoH setting first.

## Break-glass

Pi-hole down means nat-server has no DNS and cannot pull images to fix itself:

```bash
sudo tailscale set --accept-dns=false
# fix, then
sudo tailscale set --accept-dns=true
```
