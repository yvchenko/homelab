# k3s Migration Runbook

Status: **Archived runbook.** This is a checklist of the actual migration. 
Most service-specific gotchas are stored in the respective service's `README.md`.

## 1. Cluster topology — ✅ DONE (2026-07-22)

- **nat-server**: k3s **server** (control-plane), also schedulable as a worker. 
- Single control-plane node — embedded SQLite datastore (default), no etcd/HA 
- needed for a 2-node homelab.
- **gwserver** (kostyan-server): k3s **agent**, joined remotely over Tailscale. 
- Labeled with role `worker` for clarity in `kubectl get nodes`.

Confirmed state after bootstrap:
```
NAME         STATUS   ROLES           VERSION        INTERNAL-IP
gwserver     Ready    worker          v1.36.2+k3s1   100.83.127.86
nat-server   Ready    control-plane   v1.36.2+k3s1   100.83.164.52
```

Cosmetic worker label applied with:
```bash
sudo k3s kubectl label node gwserver kubernetes.io/role=worker
```

This mirrors the existing philosophy already in place for Jellyfin (two 
independent instances rather than one shared server): if gwserver drops offline 
(power, connectivity — real risk given its location), nat-server's control plane and 
its own workloads are unaffected. gwserver's pods simply won't schedule/run until it reconnects, 
which is the same failure mode as today's Compose setup on that host.

## 2. Networking: k3s over Tailscale — ✅ DONE (2026-07-22)

The two nodes aren't on the same LAN — they're bridged only via Tailscale. This needs 
explicit config, not defaults, and it took three attempts to get right. All three 
gotchas below are worth reading before anyone redoes this.

**Final, working server bootstrap (nat-server):**
```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip=100.83.164.52 \
  --advertise-address=100.83.164.52 \
  --flannel-iface=tailscale0 \
  --tls-san=nat-server.salmon-halfmoon.ts.net
```
- `--tls-san` adds the MagicDNS hostname to the apiserver cert, so the agent can join 
- via `https://nat-server.salmon-halfmoon.ts.net:6443` instead of a bare IP.
- **No `--flannel-backend` flag** — this must default to **vxlan**. See gotcha #3 below for why this matters.

**Final, working agent join (gwserver) — via env vars, not CLI flags:**
```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://nat-server.salmon-halfmoon.ts.net:6443 \
  K3S_TOKEN=<real token from /var/lib/rancher/k3s/server/node-token on nat-server> \
  INSTALL_K3S_EXEC="--node-ip=100.83.127.86 --flannel-iface=tailscale0" \
  sh -
```

**Gotcha #1 — install-script CLI arg quoting bug.** Passing `--server=...` and `--token=...` as 
separate positional args to the piped install script (`sh -s - agent --server=... --token=...`) 
caused systemd to merge both into a single quoted `ExecStart` argument, so k3s only ever saw one 
flag and failed with `Error: --token is required` even though a token was clearly passed. **Fix: 
use the `K3S_URL` / `K3S_TOKEN` env vars instead of CLI flags for the agent join** — sidesteps 
the quoting bug entirely and is the more robust method generally.

**Gotcha #2 — placeholder token literally saved as the value.** After working around gotcha #1, 
the agent hung indefinitely on "Waiting to retrieve agent configuration" (not a fast error) 
because `/etc/systemd/system/k3s-agent.service.env` had literally been set to `K3S_TOKEN=token` 
— the placeholder text, not the real token — during manual editing. k3s doesn't fail-fast on a 
bad token during this phase; it just hangs. **Always verify the actual env file contents 
(`sudo cat /etc/systemd/system/k3s-agent.service.env`) match the real token from 
`/var/lib/rancher/k3s/server/node-token`, byte for byte, before assuming a "hang" is a network 
problem.**

**Gotcha #3 — host-gw does not work over Tailscale (red herring chase).** While the agent was still 
hanging, it was misdiagnosed as an MTU problem (Tailscale's `tailscale0` defaults to MTU 1280, and 
vxlan's encapsulation overhead was a plausible-looking cause). Switched `--flannel-backend` to 
`host-gw` to eliminate encapsulation overhead — this actually broke cross-node pod networking 
outright: `host-gw` adds routes treating the peer's IP as a directly-reachable gateway, which 
requires a real L2/LAN-shaped network. Tailscale's `tailscale0` is a point-to-point tunnel interface, 
not that shape, so route installation failed with `network is unreachable` in the flannel logs 
(`route_network.go`), and cross-node pod pings got 100% packet loss. **The actual fix for gotcha #2 
was just correcting the token — the MTU theory was a red herring.** Reverted to plain `vxlan` 
(no `--flannel-backend` flag at all) and did a full clean uninstall/reinstall on both nodes; cross-node 
pod-to-pod ping then succeeded (0% loss, ~73ms RTT, consistent with real Spain↔Ukraine latency).

**Rule of thumb going forward: vxlan, not host-gw, is the correct flannel backend for this topology.** 
vxlan encapsulates (small overhead, works over any tunnel shape including Tailscale); host-gw needs a 
real LAN and will silently fail to route over a point-to-point overlay like Tailscale.

**Ports that must be reachable over the tailnet** (should already be open by default under Tailscale 
ACLs, but worth confirming if any custom ACL policy exists): 6443 (apiserver), 8472/UDP (flannel 
vxlan), 10250 (kubelet).

**Verifying a fresh join is actually healthy** — don't just trust "Active: running" in `systemctl status`,
confirm cross-node scheduling and networking explicitly:

```bash
# schedule one test pod per node
sudo k3s kubectl run test-gwserver --image=busybox --restart=Never \
  --overrides='{"spec": {"nodeSelector": {"kubernetes.io/hostname": "gwserver"}}}' -- sleep 3600
sudo k3s kubectl run test-natserver --image=busybox --restart=Never \
  --overrides='{"spec": {"nodeSelector": {"kubernetes.io/hostname": "nat-server"}}}' -- sleep 3600

# confirm placement + get pod IPs
sudo k3s kubectl get pods -o wide

# ping across nodes using the other pod's IP
sudo k3s kubectl exec test-natserver -- ping -c 4 <test-gwserver-pod-IP>

# cleanup once confirmed
sudo k3s kubectl delete pod test-gwserver test-natserver
```

## 3. Storage — ✅ DONE (2026-07-22)

Nothing here is shared storage — it's two nodes, each with their own disk holding data 
the other node doesn't have (nat-server's WD Blue 1TB at `/mnt/media`, gwserver's 1.8TB 
**at `/mnt/media`** — corrected: earlier notes said bare `/mnt`, but `/mnt` is just the 
parent mount point on gwserver too; the actual data lives one level down, same convention 
as nat-server). k3s's default `local-path-provisioner` is inherently single-node — a PVC 
provisioned on nat-server can't be read from a pod scheduled on gwserver.

Approach: **hostPath volumes + nodeSelector, not PVCs**, for anything tied to existing 
data. Two distinct cases:

1. **Labeled each node with its disk identity**, so future manifests reference a label 
instead of hardcoding a node name:

```bash
# run from nat-server (control-plane) — kubectl only works there, even when labeling gwserver
sudo k3s kubectl label node nat-server disk=nat-media
sudo k3s kubectl label node gwserver disk=kostyan-media
sudo k3s kubectl get nodes --show-labels
```

2. **Proved hostPath + label-based nodeSelector actually works**, on both nodes, with a 
throwaway pod that mounts the real media directory and lists it:

```bash
sudo k3s kubectl run test-hostpath --image=busybox --restart=Never \
  --overrides='{
    "spec": {
      "nodeSelector": {"disk": "nat-media"},
      "containers": [{
        "name": "test-hostpath",
        "image": "busybox",
        "command": ["sleep", "3600"],
        "volumeMounts": [{"name": "media", "mountPath": "/media"}]
      }],
      "volumes": [{"name": "media", "hostPath": {"path": "/mnt/media"}}]
    }
  }'

sudo k3s kubectl exec test-hostpath -- ls /media
# → real folders (movies, tv, torrents, etc.) confirmed visible from inside the pod

sudo k3s kubectl delete pod test-hostpath
```

Repeated identically on gwserver (`nodeSelector: {"disk": "kostyan-media"}`) — same result, 
real folders (`books`, `manga`, `torrents`, etc.) visible.

**Gotcha — path correction.** First attempt on gwserver pointed the hostPath at bare `/mnt` 
and returned unrelated home-directory-adjacent folders (`grim`, `nat`, `lost+found`) instead 
of media — `/mnt` is just the parent mount point, not where the actual data lives. Corrected 
to `/mnt/media`, which matches nat-server's convention exactly. **Always verify with `ls -la` 
on the actual host before trusting a remembered path.**

This mechanism (nodeSelector-by-disk-label + hostPath) is now proven and ready to reuse; it 
hasn't been applied to any real service yet — that happens per-cluster starting with 
media-download, not as separate prep work.

**Case A — single-copy data** (exists on exactly one disk): arr-stack media library, 
kostyan-server's manga/ranobe library, anything downloaded via qBittorrent. A workload touching 
this data has exactly one valid node.
- `nodeAffinity`/`nodeSelector` pins the pod to the correct node, plus a `hostPath` volume 
- pointing at the existing directory. Direct, low-risk translation of the current bind-mount 
- pattern — no data movement required.

**Case B — Syncthing-replicated data** (`/mnt/media/shared`, `/mnt/media/cloud`): this is *not* 
shared storage in the POSIX sense — it's a full independent copy on each disk, kept eventually
consistent by Syncthing itself at the application layer, not a shared filesystem k8s is aware of. 
Practically:
- A workload reading this data (e.g. co-viewing content via Jellyfin/VLC) can be scheduled on 
- *either* node via `hostPath` — both have a complete copy — but nodeAffinity should still pin it 
- to *one specific* node per deployment rather than letting it float, since a pod that gets 
- rescheduled mid-Syncthing-sync could read a partial/stale copy.
- **Concurrent writes from both nodes to the same file are the actual hazard, not scheduling** — 
- that's a Syncthing conflict-file scenario, same risk that already exists today outside k8s. 
- Nothing about k8s makes this better or worse; the existing single-writer-at-a-time usage pattern 
- (each side reads its own local copy, Syncthing propagates) carries over unchanged.
- The Syncthing pods themselves stay pinned one-per-node (as today), each syncing its own local 
- disk — k8s doesn't need to know they're related.

Reserve `local-path-provisioner` (or PVCs generally) for genuinely stateless-but-persistent app 
config that doesn't need to live at a specific existing path (e.g. a fresh appdata dir), not 
for the big media/library mounts.

## 4. GPU (NVENC on nat-server) — ✅ DONE (2026-07-22)

- k3s auto-detects `nvidia-container-runtime` on the host at startup and templates an `nvidia` 
- runtime entry directly into its embedded containerd config (`/var/lib/rancher/k3s/agent/etc/containerd/config.toml`) 
- — no manual containerd editing needed, this "just worked" alongside the existing 
- nvidia-driver-580 + nvidia-container-toolkit setup already confirmed working under Docker.
- Dedicated node label (separate from the `disk=` labels, since "has a GPU" and "which disk" 
- are different concerns that happen to coincide on this node):

```bash
sudo k3s kubectl label node nat-server gpu=nvidia-gtx1060 --overwrite
```

- No GPU exists on gwserver (AMD 7750 is decode-only, VAAPI-only anyway) — nothing to configure there. 
- The manifest's `nodeSelector` (below) ensures the device plugin never even tries to schedule there.

**Committed manifest** — `platform/nvidia-device-plugin/manifest.yaml` (full RuntimeClass + DaemonSet 
in the repo — not reproduced here). Two deltas from the stock upstream NVIDIA manifest that matter 
and are easy to lose track of:

```yaml
runtimeClassName: nvidia
nodeSelector:
  gpu: nvidia-gtx1060
```

— see the gotcha below for why the first line is load-bearing.

Apply with:
```bash
sudo k3s kubectl apply -f ~/homelab/platform/nvidia-device-plugin/manifest.yaml
```

**Gotcha — creating a RuntimeClass object does not make anything use it.** First attempt applied a 
bare `RuntimeClass` plus the *unmodified* upstream device-plugin DaemonSet (which has no 
`runtimeClassName` field at all). Result: pods ran fine under the default `runc` runtime, but the 
plugin logged `"Incompatible strategy detected auto"` and `"No devices found. Waiting indefinitely"` 
— it was never actually running through the NVIDIA runtime, so it couldn't see the GPU at all, 
even though `nvidia-smi` worked fine on the host and the RuntimeClass object existed in the cluster. 
**A RuntimeClass just registers an option; every pod spec that needs it must explicitly 
set `runtimeClassName` in its own template — nothing defaults to it automatically.** Confirmed missing 
via `kubectl get daemonset ... -o yaml | grep runtimeClassName` returning empty, then fixed by adding 
the field directly into the committed manifest (avoid patching a live object imperatively — 
see section 5 below).

**Verification — full proof the GPU is schedulable and usable inside a pod, not just visible to the node:**
```bash
sudo k3s kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o wide
# → Running, only on nat-server (nodeSelector correctly excludes gwserver)

sudo k3s kubectl logs <pod-name> -n kube-system
# → look for: "Registered device plugin for 'nvidia.com/gpu' with Kubelet"

sudo k3s kubectl describe node nat-server | grep -A 5 "Allocatable:"
# → nvidia.com/gpu: 1 should be listed

# real end-to-end test: a pod that actually requests and uses the GPU
sudo k3s kubectl run gpu-test --image=nvcr.io/nvidia/cuda:12.6.0-base-ubuntu24.04 --restart=Never \
  --overrides='{
    "spec": {
      "runtimeClassName": "nvidia",
      "nodeSelector": {"gpu": "nvidia-gtx1060"},
      "containers": [{
        "name": "gpu-test",
        "image": "nvcr.io/nvidia/cuda:12.6.0-base-ubuntu24.04",
        "command": ["nvidia-smi"],
        "resources": {"limits": {"nvidia.com/gpu": "1"}}
      }]
    }
  }'
sudo k3s kubectl logs gpu-test
# → full nvidia-smi table printed from inside the container, same GTX 1060 / driver 580.159.03
sudo k3s kubectl delete pod gpu-test
```
Confirmed working end-to-end — this is the exact mechanism the Jellyfin manifest will reuse 
later (`runtimeClassName: nvidia` + `nodeSelector: {gpu: nvidia-gtx1060}` + 
`resources.limits.nvidia.com/gpu: 1`) for NVENC.

## 5. What's declarative YAML vs. a committed script vs. genuinely throwaway

Everything up to this point was done imperatively (`kubectl run`, `kubectl patch`, `kubectl label` 
typed live) to learn and prove mechanisms fast. Going forward, sorted into three buckets so 
nothing useful gets lost in shell history:

**Committed as YAML manifests** (real k8s API objects — `platform/nvidia-device-plugin/manifest.yaml` 
is the first example): anything that creates a persistent cluster resource (DaemonSet, 
RuntimeClass, Deployment, etc.). These get `kubectl apply -f`'d from the repo, never patched live in 
prod once they exist as a file.

**Committed as scripts** (`platform/bootstrap/`) — OS-level bootstrap and idempotent node metadata 
that isn't itself a k8s API object:
- `install-server.sh` — k3s server install on nat-server, with the vxlan/host-gw gotcha as an 
- inline comment above the relevant flag.
- `join-agent.sh` — k3s agent join on gwserver, takes the token as `$1` (never hardcoded/committed — 
- same principle as `.env.example`: structure committed, real secret never committed), with the 
- CLI-quoting-bug and placeholder-token gotchas as inline comments.
- `label-nodes.sh` — all four node labels (`disk=`, `gpu=`, `kubernetes.io/role=`) in one idempotent, 
- re-runnable script (`--overwrite` flag makes re-running safe after a node rebuild).

**Genuinely throwaway, not worth keeping** — one-off `busybox`/`cuda` test pods used to prove a 
mechanism (cross-node ping, hostPath read, GPU passthrough). Correctly deleted after use. 
The *pattern* they represent is worth turning into a reusable smoke-test manifest eventually 
(`platform/smoke-tests/`) so it can be reapplied after any cluster change to confirm nothing 
regressed — noted as a later nice-to-have, not done yet.

## 6. Migrating `network_mode: host` services

Several current services bypass the Docker bridge entirely: qBittorrent, Dante, Syncthing, 
Syncplay. In k8s, the equivalent is `hostNetwork: true` on the pod spec — the pod shares the 
node's network namespace, same effect. Key carry-overs:
- **Dante**: must stay pinned to kostyan-server via nodeSelector (it's built specifically for 
- that host, bound to its `tailscale0`). `hostNetwork: true` preserves the "bound only to 
- tailscale0, restricted to 100.64.0.0/10" behavior since it's genuinely on the host's network stack.
- **qBittorrent**: same pattern, pinned to nat-server. Sonarr/Radarr still reach it via the 
- Tailscale hostname, never a Service name — that constraint doesn't go away just because it's in a pod now.
- **DHT stays disabled** — nothing about k8s changes the underlying libtorrent/SOCKS5 UDP-ASSOCIATE limitation.
- **Syncthing/Syncplay**: same `hostNetwork: true` + node pinning treatment.

## 7. New secrets handling convention
- `.env`-file substitution goes away — Compose's `.env`-in-same-directory quirk that bit the sandbox 
- cluster simply doesn't apply in k8s. Replace with `ConfigMap` (non-sensitive) + `Secret` 
- (CREDS_KEY/CREDS_IV, Venice API key, Mongo credentials, etc.).
- Secrets still never get committed to git — same principle as today's `/opt/`-only runtime secrets, 
- just enforced via `.gitignore`'d sealed values or a `secrets.example.yaml` pattern instead of `.env.example`.
- **Adopted convention (from media-sync onward): every credential value that used to live in 
- a `.env` file becomes a real k8s `Secret`, created imperatively, never committed** — even values 
- that were previously committed in plaintext directly in a compose file (e.g. vectordb's hardcoded 
- Postgres credentials in sandbox). Non-sensitive config stays as a `ConfigMap`, generated via `--from-file` 
- or `--from-env-file` from a real file committed in the repo (never hand-written inline in a ConfigMap YAML, 
- to keep one single source of truth). Applies to sandbox (section 6g) and will apply to any future service 
- still holding plaintext credentials.

## 8. Migrating the services

Rough dependency-aware order, each its own session:

1. **k3s bootstrap** — ✅ DONE (2026-07-22). Server on nat-server, agent join from gwserver, verified via `kubectl get nodes` and cross-node test-pod ping. See sections 1-2 above for exact commands and gotchas.
2. **Storage & GPU groundwork** — ✅ DONE (2026-07-22): node labels, hostPath convention, and NVIDIA device plugin all proven working (see sections 3-4). Nothing user-facing yet, just plumbing.
3. **media-download** — ✅ DONE (2026-07-23 to 2026-07-24). Arr stack + Dante + qBittorrent. See `services/media-download/README.md` — the DNS-resolution fix discovered here (`dnsPolicy: None` + explicit `dnsConfig`) applies to every `hostNetwork` workload in this migration.
4. **video** — ✅ DONE (2026-07-24). Jellyfin. See `services/video/README.md`.
5. **reading-library** — ✅ DONE (2026-07-29). Kavita + Suwayomi. See `services/reading-library/README.md`.
6. **sandbox** — ✅ DONE (2026-07-26 to 2026-07-29). LibreChat + Mongo + Meilisearch + vectordb + rag_api + backup CronJob. See `services/sandbox/README.md`.
7. **smart-home** — ✅ DONE (2026-07-24). ESPHome. See `services/smart-home/README.md`.
8. **media-sync** — ✅ DONE (2026-07-26). Syncthing, Filebrowser, Syncplay, Samba. See `services/media-sync/README.md`.
9. **audiobooks** — ✅ DONE (2026-07-29). Audiobookshelf. See `services/audiobooks/README.md`.

**All planned clusters migrated off Docker Compose to k3s.**

## 9. Closing out Docker

With every cluster confirmed running on k3s, Docker itself no longer needs to be a running daemon on either node — `docker system prune` already cleared standing containers/images. Kept the binary installed (still useful for occasional `docker build`, e.g. updating Dante's custom image) but disabled the daemon rather than fully uninstalling.

**On both nodes:**
```bash
sudo systemctl stop docker
sudo systemctl disable docker
sudo systemctl stop docker.socket
sudo systemctl disable docker.socket
```

Confirm it's actually off:
```bash
sudo systemctl status docker
```
Should show `inactive (dead)`, not `active (running)`.

When a rebuild is needed later, start it back up just for that session:
```bash
sudo systemctl start docker
# ...docker build...
sudo systemctl stop docker
```
