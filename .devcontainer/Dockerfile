FROM debian:bookworm-slim

# Xray-core version — overridable via build args in devcontainer.json
ARG XRAY_VERSION=v26.10.21
ENV XRAY_VERSION=${XRAY_VERSION}

# Project files (build context is the repository root, see devcontainer.json)
COPY .devcontainer/setup.sh /tmp/setup.sh
COPY .devcontainer/config.template.json /opt/g2ray/config.template.json
COPY .devcontainer/post-start.sh /opt/g2ray/post-start.sh
COPY .devcontainer/post-attach.sh /opt/g2ray/post-attach.sh
COPY scripts/lib.sh /opt/g2ray/scripts/lib.sh
COPY scripts/g2ray.sh /opt/g2ray/scripts/g2ray.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash curl unzip ca-certificates openssl libcap2-bin tini \
    && rm -rf /var/lib/apt/lists/* \
    && chmod +x /tmp/setup.sh \
                /opt/g2ray/post-start.sh \
                /opt/g2ray/post-attach.sh \
                /opt/g2ray/scripts/g2ray.sh \
    && /tmp/setup.sh \
    && rm -f /tmp/setup.sh \
    && ln -sf /opt/g2ray/scripts/g2ray.sh /usr/local/bin/g2ray

EXPOSE 443
