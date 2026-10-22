#!/bin/bash -e

# Create or remove a pair of network namespaces with an optionally specified
# prefix. The namespaces contain pre-configured veth and vxcan devices to run
# tests on Ethernet and CAN devices.
#
# Usage:
#   ./netns.sh up     # Create the network namespaces and bring up the devices.
#   ./netns.sh down   # Remove the network namespaces.
#   ./netns.sh check  # Check if the network namespaces exist and the devices
#                     # are present.
#
# Environment variables:
#   NETNS_PREFIX: Network namespace prefix. (optional, default: pcap)

PREFIX=${NETNS_PREFIX:-pcap}
NS_LOCAL=${PREFIX}-local
NS_REMOTE=${PREFIX}-remote
VETH=veth0
VXCAN=vxcan0

usage() {
  printf 'Usage: NETNS_PREFIX=<prefix> %s up|down|check\n' "$0" >&2
  printf 'Namespaces: %s %s\n' "$NS_LOCAL" "$NS_REMOTE" >&2
  exit 1
}

if [[ $EUID -ne 0 ]]; then
  printf 'must be root\n' >&2
  exit 1
fi

ns_exists() { [[ -e /var/run/netns/$1 ]]; }

err_missing_ns() {
  echo "netns $1 does not exist" >&2
  echo "try running netns.sh up" >&2
  exit 1
}

err_existing_ns() {
  echo "netns $1 already exists" >&2
  echo "try running netns.sh down or use a different NETNS_PREFIX" >&2
  exit 1
}

ns_del() {
  if ns_exists "$1"; then
    ip netns del "$1"
  fi
}

bring_up() {
  local  NS=$1
  printf 'Bringing up devices in network namespace %s\n' "$NS"
  ip -n "$NS" link set lo up
  ip -n "$NS" link set "$VETH" up
  ip -n "$NS" link set "$VXCAN" up
}

# Create the network namespaces and bring up the devices.
up() {
  printf 'Creating network namespaces %s and %s\n' "$NS_LOCAL" "$NS_REMOTE"

  ns_exists "$NS_LOCAL" && err_existing_ns "$NS_LOCAL"
  ns_exists "$NS_REMOTE" && err_existing_ns "$NS_REMOTE"

  trap down EXIT
  ip netns add "$NS_LOCAL"
  ip netns add "$NS_REMOTE"
  ip link add "$VETH" netns "$NS_LOCAL" type veth peer name "$VETH" netns "$NS_REMOTE"
  ip link add "$VXCAN" netns "$NS_LOCAL" type vxcan peer name "$VXCAN" netns "$NS_REMOTE"
  bring_up "$NS_LOCAL"
  bring_up "$NS_REMOTE"
  trap - EXIT
}

# Remove the network namespaces.
down() {
  printf 'Removing network namespaces %s and %s\n' "$NS_LOCAL" "$NS_REMOTE"
  ns_del "$NS_LOCAL"
  ns_del "$NS_REMOTE"
}

# Check if the network namespaces exist and the devices are present.
check() {
  local NS DEV
  ns_exists "$NS_LOCAL" || err_missing_ns "$NS_LOCAL"
  ns_exists "$NS_REMOTE" || err_missing_ns "$NS_REMOTE"
  for NS in "$NS_LOCAL" "$NS_REMOTE"; do
    for DEV in "$VETH" "$VXCAN"; do
      if ! ip -n "$NS" link show "$DEV" >/dev/null 2>&1; then
        printf '%s %s does not exist\n' "$NS" "$DEV" >&2
        exit 1
      fi
    done
  done
}

[[ ${1:-} != @(up|down|check) ]] && usage
"$1"
