#!/bin/bash

# Capture and inject packets on a pair of devices.
#
# The purpose of this script is to check which packets are captured
# by libpcap depending on the capture direction. For this purpose,
# it injects packets on both sides of a device pair and captures the
# packets on the local side.
#
# You can pass a list of device pairs to the script instead of just
# a single device pair to improve the overall runtime since the
# sleeps are then done only once.
#
# The script also uses strace to capture the setsockopt calls made by
# libpcap when capturing the packets.
#
# Use netns.sh to create two network namespaces with the given prefix
# containing pre-configured veth and vxcan devices to test Ethernet and
# CAN devices.
#
# Usage:
#   OUT=out PAIRS=veth0:veth0 NETNS_PREFIX=pcap run.sh
#
# Environment variables:
#            OUT: Output directory.         (optional, default: out)
#          PAIRS: Device pairs.             (optional, default: "veth0:veth0 vxcan0:vxcan0")
#   NETNS_PREFIX: Network namespace prefix. (optional, default: pcap)
#  CAPTURE_DELAY: Capture delay.            (optional, default: 1)
#   INJECT_DELAY: Inject delay.             (optional, default: 1)

SCRIPT_PATH=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")
CAPTURE=$SCRIPT_PATH/capture
INJECT=$SCRIPT_PATH/inject.py
PREFIX=${NETNS_PREFIX:-pcap}
CAPTURE_DELAY=${CAPTURE_DELAY:-1}
INJECT_DELAY=${INJECT_DELAY:-1}

# Fingerprints used to identify where packets come from.
FINGERPRINT_LOCAL=00DEADBEEF00
FINGERPRINT_REMOTE=00DEADBEEFFF

if [[ ! -e $CAPTURE ]]; then
  echo "capture program not found, run make" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "must be root" >&2
  exit 1
fi

"$SCRIPT_PATH/netns.sh" check || exit 1

# Result output directory.
OUT=${OUT:-out}
if [[ ! -d $OUT ]]; then
  mkdir -p "$OUT" || exit 1
fi

# Device pairs: local:remote, space-separated.
if [[ -n ${PAIRS:-} ]]; then
  read -r -a PAIR_LIST <<< "$PAIRS"
else
  PAIR_LIST=(veth0:veth0 vxcan0:vxcan0)
fi
for PAIR in "${PAIR_LIST[@]}"; do
  if [[ ! $PAIR =~ ^[^:]+:[^:]+$ ]]; then
    echo "device pair must be local:remote: $PAIR" >&2
    exit 1
  fi
done

# Print configuration.
echo "Output directory: $OUT"
echo "Capture delay: $CAPTURE_DELAY"
echo "Inject delay: $INJECT_DELAY"
echo "Device pairs:"
for PAIR in "${PAIR_LIST[@]}"; do
  echo "  $PAIR"
done

stop_captures() {
  # shellcheck disable=SC2207
  local pids=($(jobs -p))
  if ((${#pids[@]})); then
    kill "${pids[@]}" 2>/dev/null || true
  fi
}

# Clean up on exit.
trap stop_captures EXIT

# Capture packets for each combination of device pair and direction.
capture() {
  local PAIR LOCAL_DEV Q NETNS=$PREFIX-local

  for PAIR in "${PAIR_LIST[@]}"; do
    LOCAL_DEV=${PAIR%%:*}

    for Q in in out inout; do
      # grep to capture only injected packets
      # strace to capture the setsockopt calls
      ip netns exec "$NETNS" \
        strace -I2 --kill-on-exit -e setsockopt \
          -o "$OUT/$NETNS-$LOCAL_DEV-$Q.strace" \
          "$CAPTURE" -i "$LOCAL_DEV" -Q "$Q" \
        | grep -i -F --line-buffered \
          -e "$FINGERPRINT_LOCAL" \
          -e "$FINGERPRINT_REMOTE" \
        > "$OUT/$NETNS-$LOCAL_DEV-$Q" &
    done
  done
  echo "Capturing packets."
}

# Inject packets on each device of each device pair until stop_captures is called.
inject() {
  local PAIR LOCAL_DEV REMOTE_DEV

  echo "Injecting packets:"
  for PAIR in "${PAIR_LIST[@]}"; do
    LOCAL_DEV=${PAIR%%:*}
    REMOTE_DEV=${PAIR#*:}

    # Inject packets on the local side.
    echo "  $PREFIX-local $LOCAL_DEV $FINGERPRINT_LOCAL"
    ip netns exec "$PREFIX-local" "$INJECT" "$LOCAL_DEV" "$FINGERPRINT_LOCAL" &

    # Inject packets on the remote side.
    echo "  $PREFIX-remote $REMOTE_DEV $FINGERPRINT_REMOTE"
    ip netns exec "$PREFIX-remote" "$INJECT" "$REMOTE_DEV" "$FINGERPRINT_REMOTE" &
  done
}

# Report the results.
report() {
  local PAIR LOCAL_DEV Q NETNS IGNORE_OUTGOING PKTS_LOCAL PKTS_REMOTE \
        FORMAT='  %-6s %-12s %-12s %-12s %s\n' \
        NETNS=$PREFIX-local

  echo "Results:"
  for PAIR in "${PAIR_LIST[@]}"; do
    LOCAL_DEV=${PAIR%%:*}

    echo "$NETNS $LOCAL_DEV"
    echo "  local-pkt: $FINGERPRINT_LOCAL remote-pkt: $FINGERPRINT_REMOTE"
    # shellcheck disable=SC2059
    printf "$FORMAT" Q dev local-pkt remote-pkt IGNORE_OUTGOING

    for Q in in out inout; do
      RESULT_FILE=$OUT/$NETNS-$LOCAL_DEV-$Q
      STRACE_FILE=$RESULT_FILE.strace
      
      IGNORE_OUTGOING=$(awk 'match($0, /PACKET_IGNORE_OUTGOING, \[([0-9]+)\]/, m) { print m[1]; exit }' "$STRACE_FILE")
      IGNORE_OUTGOING=${IGNORE_OUTGOING:--}

      PKTS_LOCAL=$(grep -i -c -F "$FINGERPRINT_LOCAL" "$RESULT_FILE" || true)
      PKTS_REMOTE=$(grep -i -c -F "$FINGERPRINT_REMOTE" "$RESULT_FILE" || true)

      # shellcheck disable=SC2059
      printf "$FORMAT" \
        "$Q" "$LOCAL_DEV" "$PKTS_LOCAL" "$PKTS_REMOTE" "$IGNORE_OUTGOING"
    done
    echo
  done
}

capture
sleep "$CAPTURE_DELAY"
inject
sleep "$INJECT_DELAY"
stop_captures
wait || true
report
echo "Done."
