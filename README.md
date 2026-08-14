# WireGuard

WireGuard is a communication protocol and free and open-source software that implements encrypted virtual private networks (VPNs), and was designed with the goals of ease of use, high speed performance, and low attack surface. It aims to be smaller and better performing than IPsec and OpenVPN, two common tunneling protocols. The WireGuard protocol passes traffic over UDP.

wikipedia.org/wiki/WireGuard

<img src="https://camo.githubusercontent.com/0b0f5c145e201e0481fd5ff786e1757eb40ee6f5a14fd4b3da4182883f8f4143/68747470733a2f2f75706c6f61642e77696b696d656469612e6f72672f77696b6970656469612f636f6d6d6f6e732f392f39382f4c6f676f5f6f665f5769726547756172642e737667" width="30%" height="auto" alt="WireGuard logo">

## How to use this Makejail

### Requirements

Before continuing, we need to load the `if_wg(4)` driver:

```console
$ kldload if_wg
```

And add it to `loader.conf(5)` to load it at boot:

**/boot/loader.conf**:

```
if_wg_load="YES"
```

### Basic usage

The easiest way to deploy WireGuard using AppJail is as follows.

```console
$ appjail oci run -P \
    -o overwrite=force \
    -o virtualnet=":<random> default" \
    -o nat \
    -o expose="51820 proto:udp" \
    -e WG_ENDPOINT="wireguard.example.com:51820" \
    -e WG_PERSISTENTKEEPALIVE=25 \
    ghcr.io/appjail-makejails/wireguard wireguard
```

**Note**: Unlike other images, you don't need to use the `-d` parameter, since WireGuard always runs in the background.

The example above will deploy WireGuard using a [Virtual Network](https://appjail.readthedocs.io/en/latest/networking/virtual-networks/intro/), exposing port `51820/udp` to external hosts, configuring the `Endpoint` as `wireguard.example.com:51820`, and setting `PersistentKeepAlive` to `25`. Only `WG_ENDPOINT` is required, but it is recommended that you also set `WG_PERSISTENTKEEPALIVE` [to keep your firewall happy](https://www.wireguard.com/quickstart/#nat-and-firewall-traversal-persistence).

### Managing Peers

To create a new peer just run `wg-xcaler add <identity>`. `<identity>` is an arbitrary string used to identify a peer. There is no "standard" but I use a convention: `peer://<type>/<identity>/<subtype>`, for example:

```console
$ appjail oci exec wireguard wg-xcaler add peer://users/dtxdf@disroot.org/laptop
```

Similarly, to check whether a peer exists or not:

```console
$ appjail oci exec wireguard wg-xcaler check peer://users/dtxdf@disroot.org/laptop; echo $?
0
$ appjail oci exec wireguard wg-xcaler check peer://users/nonexistent@example.org/pc; echo $?
66
```

To obtain the IPv4 address of the specified peer:

```console
$ appjail oci exec wireguard wg-xcaler get-addr peer://users/DtxdF@disroot.org/laptop
192.168.7.2
```

To display the configuration file of the specified peer:

```console
$ appjail oci exec wireguard wg-xcaler show peer://users/dtxdf@disroot.org/laptop
[Interface]
PrivateKey = gDLKMPsVPfCOaztoj/+Fb3MbxgWH7/LKj7FaLq7aglg=
Address = 192.168.7.2/32
ListenPort = 51820
[Peer]
PresharedKey = qjvTKr57bALKIuN0zHYSWVL0GbZDOG2njASSDrrIOT8=
PublicKey = MhERHc1RaPGth2SnmIy9KSKgm5+xFMuo3Z8Vw2QZwFU=
AllowedIPs = 192.168.7.0/24
Endpoint = wireguard.example.com:51820
PersistentKeepalive = 25
$ # QR code.
$ appjail oci exec wireguard wg-xcaler showqr peer://users/dtxdf@disroot.org/laptop
```

To delete a specified peer:

```console
$ appjail oci exec wireguard wg-xcaler del peer://users/dtxdf@disroot.org/laptop
```

To show the network address:

```console
$ wg-xcaler get-network-addr
192.168.7.0/24
```

**Recommendation**: Note that, internally, the peers are actually a directory with a certain structure. The problem is that the names are hashed. I recommend that you keep a simple text file as a list of the peers you have created.

### Simulation using a Virtual Network

If you just want to test this image, you can use the following `Makejail` to create a jail that that connects to the server. Let's deploy the server again, but this time using a real `Endpoint`.

```console
$ appjail oci run -P \
    -o ephemeral \
    -o overwrite=force \
    -o virtualnet=":<random> default" \
    -o nat \
    -e WG_ENDPOINT=wireguard:51820 \
    -e WG_PERSISTENTKEEPALIVE=5 \
    ghcr.io/appjail-makejails/wireguard wireguard
```

Let's create a directory for our client.

```console
mkdir -p wireguard-client
cd wireguard-client
```

Next, add a new pair. Give the pair the name you want to use for the `jail` and save the configuration file in the current directory.

```console
$ appjail oci exec wireguard wg-xcaler add peer://jails/wg-client-1
$ install -m 0600 /dev/null wg-client-1.conf
$ appjail oci exec wireguard wg-xcaler show peer://jails/wg-client-1 > wg-client-1.conf
```

Next, create a makejail file named `Makejail` with the following content:

**Makejail**:

```
ARG wg_conf

OPTION start
OPTION overwrite=force
OPTION virtualnet=:<random> default
OPTION nat

RAW default_interface=`jexec -l "${APPJAIL_JAILNAME}" route -n4 get default 2> /dev/null | grep 'interface:' | cut -d' ' -f4-`

RAW if [ -z "${default_interface}" ]; then
        RAW echo "No default interface found. Cannot continue ..."
        RAW exit 1
RAW fi

VAR --make-arg-env DEFAULT_INTERFACE=${default_interface}

COPY usr

PKG wireguard-tools

# In case the user doesn't specify an absolute path, we need to
# concatenate the current working directory.
RAW if ! printf "%s" "${wg_conf}" | grep -qEe '/'; then
RAW     wg_conf="${APPJAIL_PWD}/${wg_conf}" || exit $?
RAW fi

# COPY will copy mode as-is, which is undesirable in case we want
# a correct file mode.
CMD --local-jaildir install -m 0600 ${wg_conf} usr/local/etc/wireguard/wg0.conf

# Avoid resolvconf(8) unhappiness.
CMD if grep -qEe "^DNS\s+=" /usr/local/etc/wireguard/wg0.conf; then \
        resolvconf -a "${DEFAULT_INTERFACE}" < /etc/resolv.conf || :; \
        resolvconf -u; \
    fi

SYSRC wireguard_enable=YES
SYSRC wireguard_interfaces=wg0

SERVICE wireguard start
```

It's a bit complex, but it takes many use cases into account.

It is assumed that the `usr/` directory copied by the `Makejail` remains in the same current directory. This directory is used solely to configure `pkg(8)` to use the `latest` branch.

**usr/local/etc/pkg/repos/Latest.conf**:

```
FreeBSD-ports: {
  url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}

FreeBSD-ports-kmods: {
  enabled: no
}
```

**Console**:

It's time to create our first client:

```console
$ appjail makejail -j wg-client-1 -o ephemeral -- --wg_conf wg-client-1.conf
...
$ appjail oci exec wireguard wg
interface: wg0
  public key: MhERHc1RaPGth2SnmIy9KSKgm5+xFMuo3Z8Vw2QZwFU=
  private key: (hidden)
  listening port: 51820

peer: Z+TUF5vmyHHiryC1qtzubva2pxOhe57WYYaVwoWZqkI=
  preshared key: (hidden)
  endpoint: 10.0.0.9:51820
  allowed ips: 192.168.7.2/32
  latest handshake: 41 seconds ago
  transfer: 22.87 KiB received, 3.28 KiB sent
$ appjail cmd jexec wg-client-1 ping -c4 192.168.7.1
PING 192.168.7.1 (192.168.7.1): 56 data bytes
64 bytes from 192.168.7.1: icmp_seq=0 ttl=64 time=0.181 ms
64 bytes from 192.168.7.1: icmp_seq=1 ttl=64 time=0.199 ms
64 bytes from 192.168.7.1: icmp_seq=2 ttl=64 time=0.154 ms
64 bytes from 192.168.7.1: icmp_seq=3 ttl=64 time=0.154 ms

--- 192.168.7.1 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 0.154/0.172/0.199/0.019 ms
```

To complete our simulation, let's create a second client.

```console
$ appjail oci exec wireguard wg-xcaler add peer://jails/wg-client-2
$ appjail oci exec wireguard wg-xcaler show peer://jails/wg-client-2 > wg-client-2.conf
$ install -m 0600 /dev/null wg-client-2.conf
$ appjail makejail -j wg-client-2 -o ephemeral -- --wg_conf wg-client-2.conf
...
$ appjail oci exec wireguard wg
interface: wg0
  public key: MhERHc1RaPGth2SnmIy9KSKgm5+xFMuo3Z8Vw2QZwFU=
  private key: (hidden)
  listening port: 51820

peer: JSsS4CFFtW5IZjPBnvVQLTtK/X9zYbLQcYEHeZwXHR4=
  preshared key: (hidden)
  endpoint: 10.0.0.10:51820
  allowed ips: 192.168.7.3/32
  latest handshake: 46 seconds ago
  transfer: 468 B received, 124 B sent

peer: Z+TUF5vmyHHiryC1qtzubva2pxOhe57WYYaVwoWZqkI=
  preshared key: (hidden)
  endpoint: 10.0.0.9:51820
  allowed ips: 192.168.7.2/32
  latest handshake: 54 seconds ago
  transfer: 25.21 KiB received, 4.02 KiB sent
```

**wg-client-1**:

```console
$ appjail cmd jexec wg-client-1 nc -l 8080
Hello!
```

**wg-client-2**:

```console
$ appjail cmd jexec wg-client-2 nc -v 192.168.7.2 8080
Connection to 192.168.7.2 8080 port [tcp/http-alt] succeeded!
Hello!
```

### Full Tunnel

Probably the most common way to use WireGuard is as a full tunnel, in which the VPN acts as an intermediary for a pair. However, this requires a bit more configuration, not just for WireGuard, but for our `pf(4)` inside the jail that acts as the server. Also we have to unhide `/dev/pf` device.

```console
$ default_interface=$(route -n4 get default 2> /dev/null | grep 'interface:' | cut -d' ' -f4-)
$ current_ipv4=$(ifconfig -- "${default_interface}" inet | \
    grep -m 1 -o 'inet.*' | cut -d ' ' -f 2)
$ mkdir -p /var/appjail-volumes/wireguard/etc
$ appjail oci run -P \
    -o fstab="$PWD/wireguard-etc /usr/local/etc/wireguard" \
    -o expose="51820 proto:udp" \
    -o overwrite=force \
    -o virtualnet=":wireguard default" \
    -o nat \
    -e WG_ENDPOINT=${current_ipv4}:51820 \
    -e WG_PERSISTENTKEEPALIVE=25 \
    -e WG_DNS=1.1.1.1,1.0.0.1 \
    -e WG_ALLOWEDIPS=0.0.0.0/0 \
    -o copydir="$PWD/files" \
    -o file=/etc/rc.conf \
    -o file=/etc/pf.conf \
    -o pkg=FreeBSD-pf \
    -o mount_devfs \
    -o device='include $devfsrules_hide_all' \
    -o device='include $devfsrules_unhide_basic' \
    -o device='include $devfsrules_unhide_login' \
    -o device='path pf unhide' \
    ghcr.io/appjail-makejails/wireguard wireguard
$ appjail service jail wireguard pf start
Enabling pf.
$ appjail oci exec wireguard pfctl -sn
nat on eb_wireguard inet from 192.168.7.0/24 to any -> (eb_wireguard) round-robin
```

**files/etc/rc.conf**:

```sh
pf_enable="YES"
```

**files/etc/pf.conf**:

```
ext_if="eb_wireguard"
wg_clients="192.168.7.0/24"

set skip on lo0

nat on $ext_if inet from $wg_clients to any -> ($ext_if)
```

### Dynamic Configuration

Sometimes, the default configuration isn't enough, or you simply want to modify a parameter on a peer before sending that same configuration to the user. You can use a combination of `sponge` and `initool` to modify or add a parameter on the fly.

```console
$ pkg install -y moreutils initool
...
$ appjail oci exec wireguard wg-xcaler show peer://users/dtxdf@disroot.org/laptop | sponge | initool s - Peer DNS 8.8.8.8,8.4.4.8 | tee wg-client-1.conf
```

### Arguments (stage: build)

* `wireguard_from` (default: `ghcr.io/appjail-makejails/wireguard`): Location of OCI image. See also [OCI Configuration](#oci-configuration).
* `wireguard_tag` (default: `latest`): OCI image tag. See also [OCI Configuration](#oci-configuration).

### Environment (OCI image)

* `WG_ALLOWEDIPS` (optional): See `AllowedIPs` in `wg(8)`. If you do not set this environment variable, the network address will be used.
* `WG_DNS` (optional): See `DNS` in `wg-quick(8)`.
* `WG_ENDPOINT` (mandatory): See `Endpoint` in `wg(8)`.
* `WG_MTU` (optional): See `MTU` in `wg-quick(8)`.
* `WG_NETWORK` (default: `192.168.7.0/24`): Network address.
* `WG_PERSISTENTKEEPALIVE` (optional): See `PersistentKeepalive` in `wg(8)`.
* `WG_PORT` (default: `51820`): See `ListenPort` in `wg(8)`.

## OCI Configuration

```yaml
build:
  variants:
    - tag: 15.1
      containerfile: Containerfile
      aliases: ["latest"]
      default: true
      args:
        FREEBSD_RELEASE: "15.1"
        NO_PKGCLEAN: "1"
      cache_dirs: ["pkgcache0:/var/cache/pkg"]
```

## Notes

1. This Makejail is based on an old project I worked on called `wireguard-xcaler`.
2. If you change a parameter such as endpoint or network address after recreating the jail, note that the old peers still use the old endpoint and network address, so you will have to change them manually. I do not recommend you to change those parameters after recreating the jail, keep them the same. If you want to use different parameters after recreating the jail, just don't use the same volume.
