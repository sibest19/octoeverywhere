ARG UPSTREAM_IMAGE=octoeverywhere/octoeverywhere:latest
FROM ${UPSTREAM_IMAGE}

USER root

ARG PUID=1001
ARG PGID=0

ENV PUID=${PUID}
ENV PGID=${PGID}

# Install su-exec and jq, but don't create users yet (we'll do that at runtime with dynamic PUID/PGID)
RUN apk add --no-cache su-exec jq \
    && mkdir -p /data

COPY upstream_config.json /upstream_config.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
CMD []
