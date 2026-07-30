# Project Changelog

## 2026-07-29
- Migrated sandbox cluster to k3s: LibreChat, MongoDB, Meilisearch, vectordb (pgvector), rag_api
- Moved vectordb's Postgres credentials off plaintext compose config into a Secret
- Rebuilt the Mongo backup pipeline as a CronJob, replacing backup_mongo.sh + system cron
- sandbox cluster fully migrated off Docker Compose

## 2026-07-27
- Fixed agent/skill 403 errors and stale bookmark tag-filter behavior: root cause was `Dockerfile.custom` overlaying a couple of `dist/` folders onto a pinned, stale `ghcr.io/danny-avila/librechat:latest` image instead of building from source. Switched `docker-compose.override.yml` to build from the real multi-stage `Dockerfile` against local source instead.
- Removed obsolete `patches/data-schemas-methods/conversation.cjs` and `conversation.es.js` — the fix is already present upstream in current source.
- Rebuilt and pushed updated image to `yvchenko/librechat-custom-tagging:latest` - the official one was not updated with tag logic change.
- Split creative-writing prompt (prose style + content freedom) out of per-chat parameters into two standalone LibreChat Skills (`always-apply: true`) in the sandbox project.

## 2026-07-26
- Migrated smart-home (ESPHome) to k3s; introduced a throwaway Job pattern for one-time USB flashing instead of editing the main manifest
- Migrated media-sync cluster to k3s: Syncthing, Filebrowser, Syncplay, Samba (Kustomize overlays for Syncthing/Samba's per-node config, plain DaemonSets for Filebrowser/Syncplay)
- Adopted Secrets for all credential values going forward, replacing plaintext `.env` entries
- smart-home and media-sync clusters fully migrated off Docker Compose

## 2026-07-24
- Updated LibreChat custom image to base off v0.8.7 (paired with config version v1.3.13) after. Reapplied bookmark patch logic.
- Added a small doc on how to update the image in the future

## 2026-07-24
- Migrated arr stack (Radarr, Sonarr, Prowlarr, FlareSolverr) to k3s, resolving the DNS connectivity issues open at end of previous session
- Migrated Jellyfin to k3s on both nodes; introduced Kustomize (base + per-node overlays) to handle nat-server's NVENC-specific config vs. gwserver's plain setup without duplicating manifests
- Verified NVENC hardware transcoding working correctly post-migration via live ffmpeg transcode log
- media-download and video clusters fully migrated off Docker Compose

## 2026-07-23
- Migrated media-download cluster from Docker Compose to k3s: Dante, qBittorrent, Radarr, Sonarr, Prowlarr, FlareSolverr
- Built and pushed custom Dante image to Docker Hub (`yvchenko/dante-proxy`)
- Duplicated qBittorrent and the arr stack as DaemonSets across both nodes, matching existing per-node independence pattern
- Fixed DNS resolution for hostNetwork pods (MagicDNS + general internet both failing under default dnsPolicy) via explicit `dnsPolicy: None` + `dnsConfig` with Tailscale + public resolvers

## 2026-07-22
- Started migration to k3s
- Installed k3s on both nodes, designated nat-server as control-plane and kostyan-server as a worker
- Added and verified NVIDIA device plugin for encoding (nat-server only)
- Documented bootstrap scripts for further reuse

## 2026-07-21
- Added audiobooks service — Audiobookshelf, single instance on nat-server, attaches to media_download (external)
- Custom Cardigann indexer definition for AudioBookBay, sourced from Jackett's maintained definition, mounted into Prowlarr
- Dedicated audiobooks qBittorrent category for audiobook downloads, separate from general/arr-stack flow
- Decommissioned Bazarr since it's useless after Jellyseerr removal

## 2026-07-12
- Added media-sync cluster (syncthing, filebrowser, syncplay, samba) for cross-node file replication and synchronized co-viewing between nat-server and kostyan-server
- Introduced shared/ and cloud/ Syncthing folders: shared/ for co-viewing content consumed via Syncplay + VLC/Synkplay, cloud/ for general Drive-like storage via Filebrowser
- Added a Samba share over shared/ for client devices without their own Syncthing instance

## 2025-07-11
- Restructured services into domain-clustered groups (media-download, video, reading-library, sandbox, smart-home)
- Rewrote and updated project documentation to reflect new repo structure

## 2025-07-10
- Removed Jellyseerr from the stack
- Established acquisition workflow for manga, comics, and light novels via Prowlarr

## 2025-07-09
- Brought Suwayomi to fully operational status
- Removed Komf after identifying reliability issues with Kavita integration
- Added `suwayomi-move.sh` to automate flattening of Suwayomi output into Kavita-compatible library structure
- Resolved qBittorrent and Kavita volume mount issues

## 2025-07-08
- Deployed and configured Suwayomi and Komf

## 2025-06-27
- Switched LibreChat API keys from `.env`-based config to `user_provided`, enabling per-user API keys/credits for scalability ahead of opening access to more users
- Replaced `serjs/go-socks5-proxy` with a custom-built Dante SOCKS5 proxy on kostyan-server to add proper UDP support for qBittorrent peer traffic from nat-server. 
- DHT ended up disabled since libtorrent has no SOCKS5 UDP-ASSOCIATE path for it — trackers + PeX handle peer discovery instead.

## 2025-06-12
- Attempted to run Dolphin Mistral Venice via Ollama on local hardware; hit hardware limitations
- Pivoted to Venice API platform instead

## 2025-06-11
- Added and configured FlareSolverr

## 2025-05-24
- Evaluated `serjs/go-socks5-proxy` for qBittorrent traffic routing; identified compatibility limitations with current setup
- Planned migration to Dante SOCKS proxy for improved reliability
- Temporarily configured nat-server to route all outbound traffic through kostyan-server to keep torrent traffic off the Spanish IP
- Added and configured Bazarr
- Set up GDrive backup via rclone
- Add hardware transcoding for nat-server (NVENC via the GTX 1060 3GB)

## 2025-05-23
- Migrated LibreChat deployment to nat-server
- Replicated Jellyfin + arr stack across both nodes
- Reworked media architecture into dual independent instances (one per node), each serving content from its own local HDD
- Planned Syncthing integration for cross-node library synchronization
- Configured qBittorrent on kostyan-server to route torrent traffic through a SOCKS5 proxy

## 2025-05-19
- Assembled and brought online second homelab node (`nat-server`)

## 2025-04-25
- Finalized and integrated custom chat export/migration tool
- Completed full migration of conversation history from previous AI chat platform into LibreChat

## 2025-04-19
- Published custom LibreChat Docker image
- Migrated LibreChat and Kavita to brother's server

## 2025-04-18
- Built Jellyfin + arr stack + qBittorrent on brother's server via Docker Compose
- Initialized GitOps repository

## 2025-04-16
- Jellyfin bare metal install broke due to hardware/DB issues; decided to migrate to Docker

## 2025-04-10
- Built Kavita instance on local machine

## 2025-04-08
- Brother joined the project; added his server as a node on the Tailscale network

## 2025-04-06
- Installed Jellyfin (bare metal) on brother's server; validated hardware transcoding

## 2025-04-02
- Completed bookmarks AND-logic patch (`$in` → `$all`) on custom LibreChat image

## 2025-03-27
- Set up Tailscale network for homelab connectivity

## 2025-03-25
- Decided to build a dedicated home server node; began hardware planning

## 2025-03-24
- Migrated conversation history into LibreChat using scraper output

## 2025-03-23
- Wrote Python API scraper to extract conversation history from prior AI chat platform

## 2025-03-22
- Began building LibreChat; initial stack running on local machine via Docker Desktop