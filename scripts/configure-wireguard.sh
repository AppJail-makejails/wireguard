#!/bin/sh

# Environment:
# - WG_ENDPOINT (optional)
# - WG_DNS (optional)
# - WG_PERSISTENTKEEPALIVE (optional)
# - WG_ALLOWEDIPS (0.0.0.0/0)
# - WG_SUBNET (192.168.6.0)
# - WG_PORT (51820)
# - WG_PEERS (1)
# - WG_MTU (optional)
# - WG_FORCE_UPDATE (optional)
# - WG_PEER<peer-id>_{ENDPOINT|DNS|PERSISTENTKEEPALIVE|ALLOWEDIPS|PORT|MTU|NOTE} (optional)

set -e

umask 077

. /scripts/lib.subr

RESOLVCONF="/etc/resolv.conf"
ETCDIR="/usr/local/etc/wireguard"
SRVCONF="${ETCDIR}/wg0.conf"
PEERDIR="${ETCDIR}/peers"
DNS_NS1="208.67.222.222"
DNS_NS2="208.67.220.220"
WG_FALLBACK_DNS="${DNS_NS1},${DNS_NS2}"
ENVFILE="${ETCDIR}/.env"

if [ -z "${WG_ENDPOINT}" ]; then
	default_interface=`get_default_interface`

	if [ -z "${default_interface}" ]; then
		err "Error getting default interface."
		exit 1
	fi

	WG_ENDPOINT=`get_ip4_from_iface "${default_interface}"`

	if [ -z "${WG_ENDPOINT}" ]; then
		err "Failed to get default IPv4 address."
		exit 1
	fi
fi

if [ -z "${WG_DNS}" ]; then
	if [ -f "${RESOLVCONF}" ]; then
		WG_DNS=`get_dns_list "${RESOLVCONF}"`
	fi

	if [ -z "${WG_DNS}" ]; then
		warn "Unable to retrieve a list of DNS nameservers, using the default ones: ${WG_FALLBACK_DNS}"

		WG_DNS="${WG_FALLBACK_DNS}"
	fi
fi

if [ -z "${WG_PEERS}" ]; then
	WG_PEERS=1
elif ! chk_number "${WG_PEERS}" || [ ${WG_PEERS} -lt 1 -o ${WG_PEERS} -gt 254 ]; then
	err "Invalid total of peers: ${WG_PEERS}"
	exit 1
fi

if [ -z "${WG_SUBNET}" ]; then
	WG_SUBNET="192.168.6.0"
fi

if [ -z "${WG_PORT}" ]; then
	WG_PORT="51820"
fi

if [ -z "${WG_ALLOWEDIPS}" ]; then
	WG_ALLOWEDIPS="0.0.0.0/0"
fi

if ! chk_basic_ip4 "${WG_SUBNET}"; then
	err "Invalid IPv4 address: ${WG_SUBNET}"
	exit 1
fi

envfile=`mktemp -t wireguard`

cat << EOF > "${envfile}"
WG_ENDPOINT=${WG_ENDPOINT}
WG_DNS=${WG_DNS}
WG_PERSISTENTKEEPALIVE=${WG_PERSISTENTKEEPALIVE}
WG_ALLOWEDIPS=${WG_ALLOWEDIPS}
WG_SUBNET=${WG_SUBNET}
WG_PORT=${WG_PORT}
WG_PEERS=${WG_PEERS}
WG_MTU=${WG_MTU}
EOF

if [ -z "${WG_FORCE_UPDATE}" ] && [ -f "${ENVFILE}" ]; then
	a=`sha256 -q -- "${ENVFILE}"`
	b=`sha256 -q -- "${envfile}"`

	if [ "${a}" != "${b}" ]; then
		warn "Environment variables changed, regenerating configuration files ..."
	else
		info "No changes were made to the environment variables, using the current ones."
		exit 0
	fi
fi

info "Configuring ..."

WG_SUBNET=`printf "%s" "${WG_SUBNET}" | sed -Ee 's/\.[0-9]$//'`

# server

genkeys "${ETCDIR}"

cp "${ETCDIR}/server-template.conf" "${SRVCONF}"

cat << EOF >> "${SRVCONF}"
[Interface]
Address = ${WG_SUBNET}.1/32
ListenPort = ${WG_PORT}
PrivateKey = `getprivkey "${ETCDIR}"`
EOF

if [ -n "${WG_MTU}" ] && [ "${WG_MTU}" != "none" ]; then
	echo "MTU = ${WG_MTU}" >> "${SRVCONF}"
fi

# peers

count=0

for peerid in `jot - 2 254`; do
	peerdir="${PEERDIR}/${peerid}"
	peer_address="${WG_SUBNET}.${peerid}"

	# peer environment variables
	peer_endpoint=`eval echo \\\$WG_PEER${peerid}_ENDPOINT`
	peer_dns=`eval echo \\\$WG_PEER${peerid}_DNS`
	peer_persistentkeepalive=`eval echo \\\$WG_PEER${peerid}_PERSISTENTKEEPALIVE`
	peer_allowedips=`eval echo \\\$WG_PEER${peerid}_ALLOWEDIPS`
	peer_port=`eval echo \\\$WG_PEER${peerid}_PORT`
	peer_mtu=`eval echo \\\$WG_PEER${peerid}_MTU`
	peer_note=`eval echo \\\$WG_PEER${peerid}_NOTE`

	# default
	peer_endpoint="${peer_endpoint:-${WG_ENDPOINT}}"
	peer_dns="${peer_dns:-${WG_DNS}}"
	peer_persistentkeepalive="${peer_persistentkeepalive:-${WG_PERSISTENTKEEPALIVE}}"
	peer_allowedips="${peer_allowedips:-${WG_ALLOWEDIPS}}"
	peer_port="${peer_port:-${WG_PORT}}"
	peer_mtu="${peer_mtu:-${WG_MTU}}"

	mkdir -p "${peerdir}"

	genkeys "${peerdir}"

	cat << EOF >> "${SRVCONF}"
[Peer]
AllowedIPs = ${peer_address}/32
PresharedKey = `getpresharedkey "${peerdir}"`
PublicKey = `getpubkey "${peerdir}"`
EOF

	peerconf="${peerdir}/wg.conf"

	cp "${ETCDIR}/peer-template.conf" "${peerconf}"

	cat << EOF >> "${peerconf}"
[Interface]
PrivateKey = `getprivkey "${peerdir}"`
Address = ${peer_address}/32
EOF

	if [ "${peer_port}" != "none" ]; then
		echo "ListenPort = ${peer_port}" >> "${peerconf}"
	fi

	if [ "${peer_dns}" != "none" ]; then
		echo "DNS = ${peer_dns}" >> "${peerconf}"
	fi

	if [ -n "${peer_mtu}" ] && [ "${peer_mtu}" != "none" ]; then
		echo "MTU = ${peer_mtu}" >> "${peerconf}"
	fi

	cat << EOF >> "${peerconf}"
[Peer]
PresharedKey = `getpresharedkey "${peerdir}"`
PublicKey = `getpubkey "${ETCDIR}"`
AllowedIPs = ${peer_allowedips}
Endpoint = ${peer_endpoint}:${peer_port}
EOF

	if [ -n "${peer_persistentkeepalive}" ] && [ "${peer_persistentkeepalive}" != "none" ]; then
		echo "PersistentKeepalive = ${peer_persistentkeepalive}" >> "${peerconf}"
	fi

	if [ -n "${peer_note}" ]; then
		printf "%s\n" "${peer_note}" > "${peerdir}/.note"
	fi

	count=$((count+1))

	if [ ${count} -ge ${WG_PEERS} ]; then
		break
	fi
done

mv "${envfile}" "${ENVFILE}"
