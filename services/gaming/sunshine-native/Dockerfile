# =============================================================================
# services/gaming/sunshine-native/Dockerfile
#
# Custom-built Sunshine image, replacing gameonwhales/sunshine:latest — that
# image has been unmaintained for 1+ year on Docker Hub and resolves to
# Sunshine 0.8.1, which predates the modern multi-backend capture abstraction
# (KMS/NVFBC/X11 with proper Composite-awareness) entirely. On this NVIDIA +
# headless-GPU setup, 0.8.1's plain X11 capture returned blank frames for
# GL-composited content (Steam's CEF-based UI), causing a black stream despite
# the display rendering correctly (confirmed via glxgears + glxinfo).
#
# Built from the official LizardByte .deb release, matched to nat-server's
# host OS (Ubuntu 26.04) — same precedent as the steam-native image.
# =============================================================================

FROM ubuntu:26.04

ARG SUNSHINE_DEB_URL=https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-ubuntu-26.04-amd64.deb

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        libavahi-common3 \
        libavahi-client3 \
        pulseaudio-utils \
        libcap2-bin \
    && curl -fsSL -o /tmp/sunshine.deb "${SUNSHINE_DEB_URL}" \
    && apt-get install -y -f /tmp/sunshine.deb \
    && rm -f /tmp/sunshine.deb \
    && rm -rf /var/lib/apt/lists/*

# Allow KMS capture without running as root (cap_sys_admin ~= root for this
# one purpose). Harmless even if X11 capture ends up being used instead —
# Sunshine falls back automatically if KMS isn't viable.
RUN setcap cap_sys_admin+p "$(readlink -f "$(which sunshine)")"

# Match the existing uid 1000 convention (steam-home hostPath dirs are
# chown'd 1000:1000 by the init container) — same uid-collision fix as
# steam-native, since Ubuntu 26.04 ships a default user at uid 1000.
RUN existing_user=$(getent passwd 1000 | cut -d: -f1); \
    if [ -n "$existing_user" ]; then userdel -r "$existing_user" 2>/dev/null || true; fi
RUN useradd -m -u 1000 -s /bin/bash retro

USER retro
WORKDIR /home/retro

ENTRYPOINT ["sunshine"]