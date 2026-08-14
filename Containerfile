ARG FREEBSD_RELEASE

FROM ghcr.io/appjail-makejails/base:${FREEBSD_RELEASE} AS netsum

RUN mkdir -p /netsum

WORKDIR /netsum

COPY netsum.c .

RUN set -xe; \
    \
    pkg update; \
    pkg install FreeBSD-clang FreeBSD-clibs-dev

RUN cc -O3 -s -pipe -o netsum netsum.c

FROM ghcr.io/appjail-makejails/core:${FREEBSD_RELEASE}

ARG NO_PKGCLEAN

LABEL org.opencontainers.image.title="WireGuard" \
    org.opencontainers.image.description="Fast, modern and secure VPN Tunnel" \
    org.opencontainers.image.source="https://github.com/AppJail-makejails/wireguard" \
    org.opencontainers.image.url="https://github.com/AppJail-makejails/wireguard" \
    org.opencontainers.image.vendor="DtxdF" \
    org.opencontainers.image.authors="Jesús Daniel Colmenares Oviedo <dtxdf@disroot.org>"

RUN set -xe; \
    \
    pkg update; \
    pkg install wireguard-tools libqrencode FreeBSD-bsdconfig; \
    \
    if [ -z "${NO_PKGCLEAN}" ]; then \
        pkg clean -a; \
        rm -rf /var/cache/pkg/*; \
    fi; \
    rm -rf /var/db/pkg/repos/*

COPY --from=netsum /netsum /netsum

COPY scripts /scripts

COPY wg-xcaler.sh /usr/local/bin/wg-xcaler

RUN chmod +x /usr/local/bin/wg-xcaler

ENTRYPOINT ["wg-xcaler"]
CMD ["init"]
