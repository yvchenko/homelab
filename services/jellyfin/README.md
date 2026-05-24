# Jellyfin

Self-hosted media server. Runs on Kostya's node (`kostyan-server`) and on Nat's 
node (`nat-server`) simultaneously. Serves media stored on the HDD mount at 
`/mnt/media`. Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image |
|-----------|-------|
| Media server | `jellyfin/jellyfin:latest` |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Config | `/opt/appdata/jellyfin/config` | `/config` |
| Cache | `/opt/appdata/jellyfin/cache` | `/cache` |
| Movies | `/mnt/media/movies` | `/media/movies` |
| TV | `/mnt/media/tv` | `/media/tv` |

Media mounts are read-only. Jellyfin has no write access to the media directories.

## Networking

Uses `network_mode: host` for local network discovery (DLNA broadcast).

## Node-specific configuration

The base `docker-compose.yml` contains common config. nat-server uses an
override file for NVENC and the published server URL:

```bash
docker compose -f docker-compose.yml -f docker-compose.nat.yml up -d
```

kostyan-server runs the base compose directly:

```bash
docker compose up -d
```

## Hardware transcoding (nat-server)

nat-server uses NVENC via the GTX 1060 3GB. Prerequisites:

```bash
# Install NVIDIA drivers
sudo apt install -y nvidia-driver-580

# Install NVIDIA container toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Then reboot and verify with `nvidia-smi`.

In Jellyfin: Admin → Dashboard → Playback → Transcoding → set Hardware
acceleration to NVENC, enable all codecs → Save.

## First run

```bash
# Create directories
sudo mkdir -p /opt/appdata/jellyfin/{config,cache}
sudo mkdir -p /mnt/media/{movies,tv}

# Start (example for nat-server)
docker compose -f docker-compose.yml -f docker-compose.nat.yml up -d

# Logs
docker compose logs -f jellyfin
```