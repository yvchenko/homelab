# =============================================================================
# Custom-built Steam image, built locally against nat-server's exact NVIDIA
# driver version (580.173.02) — same precedent as the Dante build: don't
# trust a third-party image to match host specifics, build it ourselves.
#
# Replaces gameonwhales/steam, which shipped either no NVIDIA init logic
# (default tag) or broken init logic that failed on a read-only EGL vendor
# directory (fedora tag). apt's own nvidia packages come with correctly
# wired glvnd config + matched 32-bit compat libs, avoiding the raw
# file-copy approach that never got glvnd routing working.
# =============================================================================

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        software-properties-common \
        ca-certificates \
        curl \
        gnupg \
    && add-apt-repository -y multiverse \
    && add-apt-repository -y restricted \
    && apt-get update

# Install the exact driver-version-matched NVIDIA GL/glvnd userspace libs.
# If libnvidia-gl-580:i386 fails due to the known libnvidia-egl-gbm1:i386
# dependency gap, fall back to installing without recommends so the 32-bit
# GLX vendor lib still lands even if EGL/GBM extras don't.
RUN apt-get install -y --no-install-recommends \
        libnvidia-gl-580 \
        libnvidia-gl-580:i386 \
    || apt-get install -y --no-install-recommends --no-install-suggests \
        libnvidia-gl-580 \
        libnvidia-gl-580:i386/now

RUN apt-get install -y --no-install-recommends \
        steam-installer \
        pulseaudio-utils \
        x11-utils \
        mesa-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Match GOW's convention: uid 1000, home directory is where the hostPath
# steam-home volume gets mounted (subPath: steam)
RUN useradd -m -u 1000 -s /bin/bash retro

USER retro
ENV HOME=/home/retro
WORKDIR /home/retro

ENTRYPOINT ["/usr/games/steam"]