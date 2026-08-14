#!/bin/sh

umask 077

. /lib.subr
. /scripts/lib.subr

WG_ETC="/usr/local/etc/wireguard"
WG_CONF="${WG_ETC}/wg0.conf"
WG_ENDPOINT_FILE="${WG_ETC}/.endpoint"
WG_MTU_FILE="${WG_ETC}/.mtu"
WG_PORT_FILE="${WG_ETC}/.port"
WG_PERSISTENTKEEPALIVE_FILE="${WG_ETC}/.persistentkeepalive"
WG_NETWORK_FILE="${WG_ETC}/.network"
WG_DNS_FILE="${WG_ETC}/.dns"
RESOLVCONF="/etc/resolv.conf"
DNS_NS1="208.67.222.222"
DNS_NS2="208.67.220.220"
WG_FALLBACK_DNS="${DNS_NS1},${DNS_NS2}"
WG_ALLOWEDIPS_FILE="${WG_ETC}/.allowedips"

if [ -z "${WG_ENDPOINT}" ]; then
    err "WG_ENDPOINT: required but not specified."
    exit 1
fi

if [ -n "${WG_PORT}" ] && ! chk_number "${WG_PORT}"; then
    err "${WG_PORT}: invalid port."
    exit 1
fi

if [ -n "${WG_NETWORK}" ]; then
    WG_NETADDR=`echo "${WG_NETWORK}" | cut -s -d/ -f1`
    if [ -z "${WG_NETADDR}" ]; then
        err "Network address must be defined!"
        exit 1
    fi

    if ! chk_basic_ip4 "${WG_NETADDR}"; then
        err "${WG_NETADDR}: invalid IPv4 address."
        exit 1
    fi

    WG_CIDR=`echo "${WG_NETWORK}" | cut -s -d/ -f2`
    if [ -z "${WG_CIDR}" ]; then
        err "CIDR must be defined!"
        exit 1
    fi

    if ! chk_number "${WG_CIDR}" || [ "${WG_CIDR}" -lt 0 -o "${WG_CIDR}" -gt 30 ]; then
        err "${WG_CIDR}: invalid CIDR."
        exit 1
    fi

    NETINFO=`/netsum/netsum -a "${WG_NETADDR}" -N 0 -n "${WG_CIDR}" 2>&1`

    errlevel=$?

    if [ ${errlevel} -ne 0 ]; then
        err "${NETINFO}"
        exit ${errlevel}
    fi

    WG_NETADDR=`echo -e "${NETINFO}" | grep NETWORK= | cut -d= -f2`
    WG_SERVER_ADDRESS=`echo -e "${NETINFO}" | grep ADDRESS= | cut -d= -f2`
    WG_NETWORK="${WG_NETADDR}/${WG_CIDR}"
else
    WG_SERVER_ADDRESS="192.168.7.1"
    WG_NETWORK="192.168.7.0/24"
fi

genkeys "${WG_ETC}"

WG_PRIVATEKEY=`getprivkey "${WG_ETC}"` || exit $?

WG_PORT="${WG_PORT:-51820}"

cat << EOF > "${WG_CONF}" || exit $?
[Interface]
Address = ${WG_SERVER_ADDRESS}/32
ListenPort = ${WG_PORT}
PrivateKey = ${WG_PRIVATEKEY}
EOF

if [ -n "${WG_MTU}" ]; then
    if ! chk_number "${WG_MTU}"; then
        err "${WG_MTU}: invalid MTU."
        exit 1
    fi

    echo "MTU = ${WG_MTU}" >> "${WG_CONF}" || exit $?

    printf "%s" "${WG_MTU}" > "${WG_MTU_FILE}" || exit $?
fi

if [ -n "${WG_DNS}" ]; then
    if [ "${WG_DNS}" = "auto" ]; then
        if [ -f "${RESOLVCONF}" ]; then
            WG_DNS=`parse_nameservers "${RESOLVCONF}"` || exit $?
        else
            WG_DNS=
        fi

        if [ -z "${WG_DNS}" ]; then
            warn "Unable to retrieve a list of nameservers, using the default ones: ${WG_FALLBACK_DNS}"

            WG_DNS="${WG_FALLBACK_DNS}"
        fi
    fi

    printf "%s" "${WG_DNS}" > "${WG_DNS_FILE}" || exit $?
fi

if [ -n "${WG_ALLOWEDIPS}" ]; then
    printf "%s" "${WG_ALLOWEDIPS}" > "${WG_ALLOWEDIPS_FILE}" || exit $?
fi

printf "%s" "${WG_ENDPOINT}" > "${WG_ENDPOINT_FILE}" || exit $?
printf "%s" "${WG_NETWORK}" > "${WG_NETWORK_FILE}" || exit $?
printf "%s" "${WG_PORT}" > "${WG_PORT_FILE}" || exit $?

if [ -n "${WG_PERSISTENTKEEPALIVE}" ]; then
    printf "%s" "${WG_PERSISTENTKEEPALIVE}" > "${WG_PERSISTENTKEEPALIVE_FILE}" || exit $?
fi
