# libpcap capture test

Checks which packets libpcap captures for each capture direction.

The script creates two network namespaces and connects them with a `veth` pair and a `vxcan` pair. It injects a recognizable packet periodically on each end of a pair, captures on the local end with `-Q in`, `-Q out`, and `-Q inout`, and records the `setsockopt` calls libpcap makes (including `PACKET_IGNORE_OUTGOING`).

```text
    pcap-local                       pcap-remote
.---------------.                 .---------------.
|     veth0   ---------veth----------   veth0     |
|               |                 |               |
|     vxcan0  ---------vxcan---------   vxcan0    |
'---------------'                 '---------------'
```

## Requirements

- Linux with `veth` and `vxcan` support
- `iproute2`, Python 3, `strace`, and root (network namespaces and raw sockets)
- libpcap, found with `pkg-config`

## Build

```sh
make
```

Set `PKG_CONFIG_APTH` to chose which libpcap to link.

## Run

```sh
sudo ./netns.sh up
sudo ./run.sh
sudo ./netns.sh down
```

* `NETNS_PREFIX` (default `pcap`) names the namespaces `<prefix>-local` and `<prefix>-remote`. Each namespace has `veth0` and `vxcan0`.
* `PAIRS` is a space-separated list of `local:remote` device names. The default is `veth0:veth0 vxcan0:vxcan0`.
* `OUT` (default `out`) is the directory for capture logs and strace output.

```sh
sudo OUT=out PAIRS="veth0:veth0" NETNS_PREFIX=pcap ./run.sh
```

### Example

```
# ./netns.sh up
Creating network namespaces pcap-local and pcap-remote
Bringing up devices in network namespace pcap-local
Bringing up devices in network namespace pcap-remote
```

```
# ./run.sh
Output directory: out
Device pairs:
  veth0:veth0
  vxcan0:vxcan0
Capturing packets.
Injecting packets:
  pcap-local veth0 00DEADBEEF00
  pcap-remote veth0 00DEADBEEFFF
  pcap-local vxcan0 00DEADBEEF00
  pcap-remote vxcan0 00DEADBEEFFF
Results:
pcap-local veth0
  local-pkt: 00DEADBEEF00 remote-pkt: 00DEADBEEFFF
  Q      dev          local-pkt    remote-pkt   IGNORE_OUTGOING
  in     veth0        0            10           1
  out    veth0        10           0            0
  inout  veth0        10           10           0

pcap-local vxcan0
  local-pkt: 00DEADBEEF00 remote-pkt: 00DEADBEEFFF
  Q      dev          local-pkt    remote-pkt   IGNORE_OUTGOING
  in     vxcan0       10           10           1
  out    vxcan0       10           0            0
  inout  vxcan0       10           10           0

Done.
```

```
# ./netns.sh down
Removing network namespaces pcap-local and pcap-remote
```

You can see that for CAN devices, `-Q in` does not really work in `libpcap` (libpcap-1.11.0-79-g1fd55f34) as it captures packets injected at both ends when it should only capture incoming (`remote-pkt`) packets.