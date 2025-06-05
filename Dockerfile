FROM docker.io/library/golang:1-bookworm

ENV CRYPKI_DIR=/go/src/github.com/theparanoids/crypki
COPY ./crypki ${CRYPKI_DIR}
WORKDIR ${CRYPKI_DIR}
RUN go get -v ./... && \
    go build -o crypki-bin ${CRYPKI_DIR}/cmd/crypki && \
    go build -o gen-cacert ${CRYPKI_DIR}/cmd/gen-cacert

FROM docker.io/library/debian:bookworm-slim

ARG VERSION
# date -u +'%Y-%m-%dT%H:%M:%SZ'
ARG BUILD_DATE
# git rev-parse --short HEAD
ARG VCS_REF

LABEL org.opencontainers.image.version=$VERSION
LABEL org.opencontainers.image.revision=$VCS_REF
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.title="The Paranoids Crypki with SoftHSM for Athenz"
LABEL org.opencontainers.image.authors="ctyano <ctyano@duck.com>"
LABEL org.opencontainers.image.vendor="ctyano <ctyano@duck.com>"
LABEL org.opencontainers.image.licenses="Private"
LABEL org.opencontainers.image.url="ghcr.io/ctyano/crypki-softhsm"
LABEL org.opencontainers.image.documentation="https://www.athenz.io/"
LABEL org.opencontainers.image.source="https://github.com/theparanoids/crypki"

ENV CRYPKI_DIR=/go/src/github.com/theparanoids/crypki
WORKDIR /opt/crypki

COPY --from=0 ${CRYPKI_DIR}/crypki-bin /usr/bin/
COPY --from=0 ${CRYPKI_DIR}/gen-cacert /usr/bin/
COPY ./crypki/docker-softhsm/init_hsm.sh /opt/crypki
COPY ./crypki/docker-softhsm/crypki.conf.sample /opt/crypki
COPY ./docker-entrypoint.sh /opt/crypki

RUN mkdir -p /var/log/crypki /opt/crypki /opt/crypki/slot_pubkeys \
&& apt update \
&& apt install -y softhsm2 opensc openssl tini curl \
&& /bin/bash -x /opt/crypki/init_hsm.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/crypki/docker-entrypoint.sh"]
