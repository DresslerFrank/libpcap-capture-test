#!/usr/bin/env python3

import socket
import struct
import sys
import time

ARPHRD_ETHER = 1
ARPHRD_CAN = 280
ARPHRD_LOOPBACK = 772
ETH_P_802_EX1 = 0x88B5
INTERVAL = 0.1


def main():
  """Periodically inject packets with a 6 byte fingerprint until stopped."""

  if len(sys.argv) != 3:
    sys.exit("usage: %s <device> <12 hex digits>" % sys.argv[0])
  dev = sys.argv[1]

  fp = bytes.fromhex(sys.argv[2])
  if len(fp) != 6:
    sys.exit("fingerprint must be 6 bytes")

  with open("/sys/class/net/%s/type" % dev) as f:
    arphrd = int(f.read())

  if arphrd == ARPHRD_ETHER or arphrd == ARPHRD_LOOPBACK:
    # dst MAC broadcast, src MAC fingerprint
    frame = b"\xff" * 6 + fp + struct.pack("!H", ETH_P_802_EX1)
    raw = socket.socket(socket.AF_PACKET, socket.SOCK_RAW,
                        socket.htons(ETH_P_802_EX1))
    raw.bind((dev, 0))
  elif arphrd == ARPHRD_CAN:
    # fingerprint in payload
    frame = struct.pack("=IB3x8s", 0, 8, fp + b"\x00\x00")
    raw = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
    raw.bind((dev,))
  else:
    sys.exit("unsupported device type %d" % arphrd)

  while True:
    raw.send(frame)
    time.sleep(INTERVAL)


if __name__ == "__main__":
  main()
