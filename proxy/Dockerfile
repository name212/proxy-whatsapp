# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# License found in the LICENSE file in the root directory
# of this source tree.
FROM haproxy:lts-alpine

# Install dependencies for healthcheck support
USER root
RUN apk --no-cache add curl openssl jq bash

WORKDIR /

RUN mkdir -p /opt/whatsapp-proxy && \
    mkdir -p /home/haproxy/certs && \
    mkdir -p /user-config && \
    touch /user-config/override.env && \
    chown haproxy:haproxy /home/haproxy/certs && \
    chmod 700 /home/haproxy/certs

# Copy src files
COPY --chown=root:haproxy src/ /opt/whatsapp-proxy

# chmod and chown files
RUN chmod +x /opt/whatsapp-proxy/start.sh && \
    chmod +x /opt/whatsapp-proxy/generate-certs.sh && \
    chmod +x /opt/whatsapp-proxy/healthcheck.sh && \
    chmod 640 /opt/whatsapp-proxy/start-config-docker.env && \
    chmod 640 /opt/whatsapp-proxy/whatsapp-haproxy.cfg

HEALTHCHECK --interval=10s --start-period=10s CMD bash -c 'source /opt/whatsapp-proxy/start-config-docker.env && /opt/whatsapp-proxy/healthcheck.sh'

# Revert to the haproxy user for runtime operation
USER haproxy

WORKDIR /opt/whatsapp-proxy

# Generate a runtime certificate and start HAProxy
CMD ["/opt/whatsapp-proxy/start.sh", "-c", "/user-config/override.env", "-c", "/opt/whatsapp-proxy/start-config-docker.env"]
