# WireGuard

WireGuard is a communication protocol and free and open-source software that implements encrypted virtual private networks (VPNs), and was designed with the goals of ease of use, high speed performance, and low attack surface. It aims to be smaller and better performing than IPsec and OpenVPN, two common tunneling protocols. The WireGuard protocol passes traffic over UDP.

wikipedia.org/wiki/WireGuard

![wireguard logo](https://upload.wikimedia.org/wikipedia/commons/9/98/Logo_of_WireGuard.svg)

## How to use this Makejail

### Requirements

Before continuing, we need to load the `if_wg(4)` driver:

```sh
kldload if_wg
```

And add it to `loader.conf(5)` to load it at boot:

**/boot/loader.conf**:

```
if_wg_load="YES"
```

### Basic usage

```sh
mkdir -p .volumes/wg-etc
appjail makejail \
	-j wireguard \
	-f gh+AppJail-makejails/wireguard
	-o virtualnet=":<random> default" \
	-o nat \
	-o expose="51820 proto:udp" \
	-o volume="$PWD/.volumes/wg-etc wireguard-etc <volumefs>" \
	-V WG_ENDPOINT=192.168.1.112 \
	-V WG_PERSISTENTKEEPALIVE=25
```

### List all peers



```sh
appjail run \
	-s ls-peers \
	wireguard
```

### Show a given peer

```sh
appjail run \
	-s show-peer \
	-V WG_PEERID=2 \
	wireguard
```

#### Environment

* `WG_PEERID` (mandatory): Peer ID.
* `WG_HIDE_QRCODE` (optional): Set this environment variable to not display the QR code.

### Search a peer

```sh
appjail run \
	-s search-peer \
	-V WG_PATTERN="something" \
	wireguard
```

#### Environment

* `WG_PATTERN` (default: `.+`): Pattern to find matches.

### Firewall / Packet Filter

WireGuard is not intended to be a second firewall, so we must combine it with one of our choice if we want to do some more things, such as NAT.

```console
# tree -pug
[drwxr-xr-x dtxdf    wheel   ]  .
├── [-rw-r--r-- dtxdf    wheel   ]  Makejail
└── [drwxr-xr-x root     wheel   ]  files
    └── [drwxr-xr-x root     wheel   ]  etc
        ├── [-rw-r--r-- root     wheel   ]  pf.conf
        └── [-rw-r--r-- root     wheel   ]  rc.conf

3 directories, 3 files
```

**files/etc/pf.conf**:

```
ext_if="eb_wireguard"
wg_clients="192.168.6.0/24"
wg_ports="{51820}"

set skip on lo0

nat on $ext_if inet from $wg_clients to any -> ($ext_if)
```

**files/etc/rc.conf**:

```
gateway_enable="YES"
pf_enable="YES"
```

**Makejail**:

```
INCLUDE gh+AppJail-makejails/wireguard

OPTION virtualnet=:wireguard default
OPTION nat
OPTION expose=51820 proto:udp
OPTION fstab=$PWD/.volumes/wg-etc wireguard-etc <volumefs>
OPTION device=include \$devfsrules_hide_all
OPTION device=include \$devfsrules_unhide_basic
OPTION device=include \$devfsrules_unhide_login
OPTION device=path pf unhide
OPTION mount_devfs
OPTION copydir=files
OPTION file=/etc/rc.conf
OPTION file=/etc/pf.conf

SERVICE pf restart
```

```sh
appjail makejail \
    -j wireguard \
    -V WG_ENDPOINT=192.168.1.112 \
    -V WG_PERSISTENTKEEPALIVE=25 \
        -- \
        --wg_tag 14.0
```

### Arguments

* `wg_tag` (default: `13.3`): See [#tags](#tags).
* `wg_srvconf` (default: `files/server-template.conf`): Template for the server.
* `wg_peerconf` (default: `files/peer-template.conf`): Template for the peer.

### Environment

* `WG_ENDPOINT` (optional): See `Endpoint` in `wg(8)`. If undefined, an attempt is made to obtain an IPv4 address from the default interface, which of course may not make sense, so it is advisable to set this environment variable explicitly.
* `WG_DNS` (optional): See `DNS` in `wg-quick(8)`. DNS servers for each peer. If undefined, the `resolv.conf(5)` file is used and if it does not exist, OpenDNS nameservers will be used.
* `WG_PERSISTENTKEEPALIVE` (optional): See `PersistentKeepalive` in `wg(8)`.
* `WG_ALLOWEDIPS` (default: `0.0.0.0/0`): See `AllowedIPs` in `wg(8)`.
* `WG_SUBNET` (default: `192.168.6.0`): A 24-bit long network address. The last octet is ignored, but 0 is used as a convention.
* `WG_PORT` (default: `51820`): See `ListenPort` in `wg(8)`.
* `WG_PEERS` (default: `1`): Total number of pairs to create. A valid number is between 1 and 253. Note that 2 is the first peer ID assigned, 1 is reserved by the server.
* `WG_MTU` (optional): See `MTU` in `wg-quick(8)`. Set this environment variable to `none` to leave it unspecified.
* `WG_FORCE_UPDATE` (optional): The configuration files are not regenerated if the environment variables `WG_ENDPOINT`, `WG_DNS`, `WG_PERSISTENTKEEPALIVE`, `WG_ALLOWEDIPS`, `WG_SUBNET`, `WG_PORT`, `WG_PEERS` and `WG_MTU` are not modified, but as you can see, peer environment variables are not taken into account, so this environment variable is used to forcibly regenerate the configuration files.
* `WG_PEER<peer-id>_ENDPOINT`: Set a different `Endpoint` than global.
* `WG_PEER<peer-id>_DNS`: Set a different `DNS` than global. Set this environment variable to `none` to leave it unspecified.
* `WG_PEER<peer-id>_PERSISTENTKEEPALIVE`: Set a different `PersistentKeepalive` than global. Set this environment variable to `none` to leave it unspecified.
* `WG_PEER<peer-id>_ALLOWEDIPS`: Set a different `Endpoint` than global.
* `WG_PEER<peer-id>_PORT`: Set a different `ListenPort` than global. Set this environment variable to `none` to leave it unspecified.
* `WG_PEER<peer-id>_MTU`: Set a different `MTU` than global. Set this environment variable to `none` to leave it unspecified.
* `WG_PEER<peer-id>_NOTE`: A simple note, useful when searching.

## Tag

| Tag    | Arch    | Version        | Type   |
| ------ | ------- | -------------- | ------ |
| `13.3` | `amd64` | `13.3-RELEASE` | `thin` |
| `14.0` | `amd64` | `14.0-RELEASE` | `thin` |
