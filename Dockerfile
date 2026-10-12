ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG APT_MIRROR=""
RUN if [ -n "$APT_MIRROR" ]; then \
        sed -i "s|http://archive.ubuntu.com|${APT_MIRROR}|g" /etc/apt/sources.list && \
        sed -i "s|http://security.ubuntu.com|${APT_MIRROR}|g" /etc/apt/sources.list; \
    fi && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        parted \
        gdisk \
        e2fsprogs \
        dosfstools \
        kpartx \
        ca-certificates \
        curl \
        wget \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/entware-installers

COPY entrypoint.sh /opt/keenetic/entrypoint.sh
COPY lib/ /opt/keenetic/lib/
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/keenetic/entrypoint.sh /opt/scripts/*

ENTRYPOINT ["/opt/keenetic/entrypoint.sh"]
