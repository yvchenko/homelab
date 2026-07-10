FROM ubuntu:24.04

ARG DANTE_VERSION

RUN apt-get update && \
    apt-get install -y --no-install-recommends dante-server=${DANTE_VERSION} && \
    rm -rf /var/lib/apt/lists/*

COPY danted.conf /etc/danted.conf

EXPOSE 1080
CMD ["danted", "-f", "/etc/danted.conf"]