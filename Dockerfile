FROM octoeverywhere/octoeverywhere:latest

ARG PUID=1001
ARG PGID=0
ARG UPSTREAM_ENTRYPOINT='["/app/octoeverywhere-env/bin/python","-m","docker_octoeverywhere"]'
ARG UPSTREAM_CMD='null'

ENV PUID=${PUID}
ENV PGID=${PGID}

# Store the discovered upstream entrypoint and cmd for the wrapper script
RUN echo "UPSTREAM_ENTRYPOINT=${UPSTREAM_ENTRYPOINT}" > /upstream_config && \
    echo "UPSTREAM_CMD=${UPSTREAM_CMD}" >> /upstream_config && \
    echo "Stored upstream config: ENTRYPOINT=${UPSTREAM_ENTRYPOINT}, CMD=${UPSTREAM_CMD}"

RUN apk add --no-cache su-exec jq \
    && mkdir -p /data && chown -R ${PUID}:${PGID} /data

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
