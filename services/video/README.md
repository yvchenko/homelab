# Video

Self-hosted media server (Jellyfin). Runs on Kostya's node (`kostyan-server`)
and on Nat's node (`nat-server`) simultaneously — two independent instances,
each reading its own local HDD, not a shared library. Accessible over
Tailscale only — not exposed to the public internet.

## Stack

| Component | Image |
|-----------|-------|
| Jellyfin | `jellyfin/jellyfin:latest` |

Two separate k8s Deployments in the `video` namespace — `jellyfin-nat` and
`jellyfin-kostyan` — generated from a single shared Kustomize base plus a
small per-node overlay, rather than two full manifests. This keeps the
common config (volumes, DNS settings, `hostNetwork`) in exactly one place;
each overlay only states what's actually different for that node.

```
services/video/jellyfin/
├── base/
│   ├── deployment.yaml
│   └── kustomization.yaml
└── overlays/
    ├── nat/kustomization.yaml       # GPU passthrough + published URL
    └── kostyan/kustomization.yaml   # no GPU, base config only
```

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Config | `/opt/appdata/jellyfin/config` | `/config` |
| Cache | `/opt/appdata/jellyfin/cache` | `/cache` |
| Movies | `/mnt/media/movies` | `/media/movies` |
| TV | `/mnt/media/tv` | `/media/tv` |

All mounted via `hostPath` in the base manifest. Media mounts are read-only.
Jellyfin has no write access to the media directories.

## Networking

Runs with `hostNetwork: true` (the k8s equivalent of Compose's
`network_mode: host`) for local network discovery. No dependency on any
other namespace — Jellyfin reads from `/mnt/media` directly and doesn't talk
to arr/qBittorrent over the wire.

**DNS**: also carries the `dnsPolicy: None` + explicit `dnsConfig` fix
(Tailscale's resolver + a public fallback) used across every `hostNetwork`
workload in this cluster. Without it, a `hostNetwork` pod's default DNS
resolution is unreliable for both Tailscale MagicDNS names and ordinary
internet domains — Jellyfin needs the latter for its own metadata-provider
lookups (TheMovieDB, etc.), so this isn't optional here even though Jellyfin
itself has no Tailscale-hostname-specific config.

## Node-specific configuration

Base config lives in `base/deployment.yaml` — shared by both nodes. Each
overlay patches in only what differs:

- **`overlays/nat`**: adds `nodeSelector: {disk: nat-media}`,
  `runtimeClassName: nvidia`, the `JELLYFIN_PublishedServerUrl` env var, GPU
  env vars, a `resources.limits.nvidia.com/gpu: 1` request, and the
  `/dev/dri` device mount.
- **`overlays/kostyan`**: adds only `nodeSelector: {disk: kostyan-media}` —
  no GPU passthrough (kostyan-server's AMD 7750 is VAAPI decode-only, not
  wired up here yet).

Apply with `-k` (Kustomize mode), not `-f`:

```bash
sudo k3s kubectl apply -k services/video/jellyfin/overlays/nat
sudo k3s kubectl apply -k services/video/jellyfin/overlays/kostyan
```

## Hardware transcoding (nat-server)

nat-server uses NVENC via the GTX 1060 3GB. Host-level prerequisites are
unchanged from before — the driver and container toolkit still need to be
installed directly on the node, independent of k8s:

```bash
# Install NVIDIA drivers
sudo apt install -y nvidia-driver-580

# Install NVIDIA container toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
```

Reboot and verify with `nvidia-smi`. **Do not run `nvidia-ctk runtime
configure --runtime=docker`** — that step is Docker-specific and no longer
applies. k3s's embedded containerd auto-detects the installed
`nvidia-container-runtime` on its own and templates an `nvidia` runtime
entry into its own config automatically; no manual containerd editing
needed either.

The actual k8s-side GPU wiring (the `RuntimeClass`, the NVIDIA device
plugin DaemonSet, and the `gpu=nvidia-gtx1060` node label) is cluster-level
platform config, not part of this service — see
`platform/nvidia-device-plugin/`. This service's overlay just consumes it
via `runtimeClassName: nvidia` + the GPU resource request.

In Jellyfin: Admin → Dashboard → Playback → Transcoding → set Hardware
acceleration to NVENC, enable all codecs → Save.

**Verifying NVENC is actually being used**: don't rely on `nvidia-smi`
alone — it only shows non-zero utilization while a transcode is *actively*
running at that exact moment, so checking it between streams looks
identical to a real failure. The reliable check is Jellyfin's own ffmpeg
transcode log:

```bash
sudo k3s kubectl exec -n video <jellyfin-nat-pod-name> -- \
  ls /config/log
sudo k3s kubectl exec -n video <jellyfin-nat-pod-name> -- \
  cat /config/log/FFmpeg.Transcode-<latest>.log
```

Look for `h264_nvenc` in the invoked ffmpeg command and
`(h264 (native) -> h264 (h264_nvenc))` in the stream-mapping line — that's
confirmed hardware encoding, independent of what `nvidia-smi` shows at the
moment you happen to check it.

## First run

```bash
# Create directories (both nodes)
sudo mkdir -p /opt/appdata/jellyfin/{config,cache}
sudo mkdir -p /mnt/media/{movies,tv}

# Stop the old Docker container first if migrating a live instance —
# the container was named "video", not "jellyfin"
docker stop video

sudo k3s kubectl create namespace video
sudo k3s kubectl apply -k services/video/jellyfin/overlays/nat
sudo k3s kubectl apply -k services/video/jellyfin/overlays/kostyan
sudo k3s kubectl get pods -n video -o wide

# Logs
sudo k3s kubectl logs -n video <pod-name> -f
```

## Known gotchas

* The Docker container's name (`video`) doesn't match the image/service
  name (`jellyfin`) — easy to `docker stop jellyfin` and have it silently
  no-op. Always check `docker ps` for the real container name before
  assuming a stop/rm succeeded.
* `hostNetwork: true` pods do **not** reliably resolve DNS by default —
  neither `dnsPolicy: ClusterFirstWithHostNet` (the officially "recommended"
  setting for this exact scenario) nor `dnsPolicy: Default` actually worked
  here. Only explicit `dnsPolicy: None` + a manually specified `dnsConfig`
  (Tailscale's resolver plus a public fallback, not this node's own
  ISP-specific resolver — that breaks on the *other* node if reused as-is
  in a shared manifest) resolved it correctly.
* Creating a `RuntimeClass` object does not make anything use it — every
  pod spec that needs GPU passthrough must explicitly set
  `runtimeClassName: nvidia` itself; nothing defaults to it automatically.
