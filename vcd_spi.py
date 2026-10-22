#!/usr/bin/env python3
"""vcd_spi.py — parse a virt-harness VCD and decode SPI transactions + UART.

Streams a (possibly huge) VCD file, tracks the virt::Virt pin signals, and
reports:

  * SPI flash transactions: CS low starts a frame; MOSI is sampled on
    rising CK edges.  The first 8 bits are the command (expect 0x03 READ),
    the next 24 bits the address; after that MISO streams back, 8 bits per
    byte, until CS deasserts.
  * UART TX bytes (115200 8N1): decoded from *timestamps*, not edge
    counts, so consecutive equal data bits are handled correctly.  The bit
    period is auto-calibrated as the minimum interval between TX
    transitions (or from --baud, in VCD time units).

Usage: vcd_spi.py dump.vcd [--max-transactions N] [--baud PS]
"""

import sys
import argparse


def decode_uart(transitions: list[tuple[int, int]], period: int) -> tuple[list[int], list[int]]:
    """Bit-slot decode of UART frames.

    transitions: (time, level_after) pairs, in order.
    period: one bit period in time units.
    Returns (bytes, frame_start_times).
    """
    out: list[int] = []
    starts: list[int] = []
    i = 0
    n = len(transitions)
    while i < n:
        t, v = transitions[i]
        if v != 0:
            i += 1
            continue
        # Start bit at time t (line falls to 0).
        slots = [0] + [None] * 9  # slot 0 = start bit
        frame_end = t + 10 * period
        # Walk transitions while inside the frame.
        j = i + 1
        cur_level = 0
        cur_start = t
        while j < n and transitions[j][0] < frame_end:
            tj, vj = transitions[j]
            s0 = (cur_start - t) // period
            s1 = (tj - t) // period
            for s in range(s0, s1):
                if 1 <= s <= 9:
                    slots[s] = cur_level
            cur_level = vj
            cur_start = tj
            j += 1
        # Fill the rest of the frame with the final level.
        s0 = (cur_start - t) // period
        for s in range(s0, 10):
            if 1 <= s <= 9:
                slots[s] = cur_level
        if all(slots[s] is not None for s in range(10)):
            stop = slots[9]
            if stop == 1:
                data = 0
                for k in range(1, 9):
                    if slots[k]:
                        data |= 1 << (k - 1)
                out.append(data)
                starts.append(t)
        i = j if j > i else i + 1
    return out, starts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("--max-transactions", type=int, default=40)
    ap.add_argument("--baud", type=float, default=None,
                    help="UART baud; bit period = 1e12/baud in ps "
                         "(default: auto-calibrate from min TX interval)")
    args = ap.parse_args()

    # ── Header: map id codes to signal names ──
    ids: dict[str, list[str]] = {}
    scope: list[str] = []
    with open(args.vcd, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("$var"):
                parts = line.split()
                idcode, name = parts[3], parts[4]
                full = ".".join(scope + [name])
                ids.setdefault(idcode, []).append(full)
            elif line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                if scope:
                    scope.pop()
            elif line.startswith("$enddefinitions"):
                break

    def find(suffix: str) -> str | None:
        for idcode, names in ids.items():
            for full in names:
                if full == suffix or full.endswith("." + suffix):
                    return idcode
        return None

    id_ck = find("spi_ck")
    id_cs = find("spi_cs")
    id_mosi = find("spi_mosi")
    id_miso = find("spi_miso")
    id_tx = find("tx")
    if not all([id_ck, id_cs, id_mosi, id_miso]):
        for idcode, names in sorted(ids.items()):
            print("  %s -> %s" % (idcode, names))
        sys.exit("error: spi signals not found")

    # ── Pass 1: stream value changes ──
    vals: dict[str, int] = {}

    spi_state = "idle"      # idle | cmd | addr | data | other
    cmd_bits: list[int] = []
    addr_bits: list[int] = []
    tx_addr = 0
    rx_bits: list[int] = []
    tx_bytes: list[int] = []
    txn_start_t = 0
    transactions: list[tuple[int, int, int, list[int]]] = []

    tx_transitions: list[tuple[int, int]] = []
    time_now = 0

    with open(args.vcd, "r", errors="replace") as f:
        in_header = True
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if in_header:
                if line.startswith("$enddefinitions"):
                    in_header = False
                continue
            if line[0] == "#":
                time_now = int(line[1:])
                continue
            if line[0] == "$":
                continue
            if line[0] in "01xzXZ" and len(line) >= 2:
                val = line[0]
                idcode = line[1:]
                if idcode not in (id_ck, id_cs, id_mosi, id_miso, id_tx):
                    continue
                v = 0 if val in "0xXzZ" else 1
                vals[idcode] = v

                # ── SPI: sample MOSI on CK rising edges ──
                if idcode == id_ck and v == 1 and vals.get(id_cs, 1) == 0:
                    mosi = vals.get(id_mosi, 0)
                    if spi_state == "idle":
                        txn_start_t = time_now
                        cmd_bits.append(mosi)
                        if len(cmd_bits) == 8:
                            cmd = 0
                            for b in cmd_bits:
                                cmd = (cmd << 1) | b
                            cmd_bits = []
                            spi_state = "addr" if cmd == 0x03 else "other"
                    elif spi_state == "addr":
                        addr_bits.append(mosi)
                        if len(addr_bits) == 24:
                            tx_addr = 0
                            for b in addr_bits:
                                tx_addr = (tx_addr << 1) | b
                            addr_bits = []
                            rx_bits = []
                            tx_bytes = []
                            spi_state = "data"
                    elif spi_state == "data":
                        rx_bits.append(vals.get(id_miso, 0))
                        if len(rx_bits) == 8:
                            byte = 0
                            for i, b in enumerate(rx_bits):
                                if b:
                                    byte |= 1 << i
                            tx_bytes.append(byte)
                            rx_bits = []

                # ── SPI frame end: CS rising edge ──
                if idcode == id_cs and v == 1:
                    if spi_state == "data":
                        transactions.append((txn_start_t, 0x03, tx_addr, tx_bytes))
                        if len(transactions) >= args.max_transactions:
                            break
                    spi_state = "idle"
                    cmd_bits = []
                    addr_bits = []

                # ── UART TX transitions ──
                if idcode == id_tx:
                    if not tx_transitions or tx_transitions[-1][1] != v:
                        tx_transitions.append((time_now, v))

                if len(transactions) >= args.max_transactions:
                    break

    # ── Calibrate the UART bit period ──
    if args.baud:
        period = int(round(1e12 / args.baud))
    else:
        deltas = [b[0] - a[0] for a, b in zip(tx_transitions, tx_transitions[1:])
                  if b[0] > a[0]]
        if not deltas:
            period = 0
        else:
            period = min(deltas)

    # ── Pass 2: decode UART frames in memory ──
    uart_bytes: list[int] = []
    uart_starts: list[int] = []
    if period > 0:
        uart_bytes, uart_starts = decode_uart(tx_transitions, period)

    # ── Report ──
    print("=== SPI transactions ===")
    for t, cmd, addr, data in transactions:
        hexdata = " ".join("%02x" % b for b in data[:16])
        more = " ..." if len(data) > 16 else ""
        print("t=%d cmd=%02x addr=0x%06x -> [%s%s] (%d bytes)"
              % (t, cmd, addr, hexdata, more, len(data)))
    if not transactions:
        print("(none)")

    print()
    print("=== UART TX bytes ===")
    if not uart_bytes:
        print("(none)")
    for t, b in zip(uart_starts, uart_bytes):
        ch = chr(b) if 32 <= b < 127 else "\\x%02x" % b
        print("t=%d byte=0x%02x '%s'" % (t, b, ch))
    print("(%d bytes; bit period %s)" % (len(uart_bytes), period))


if __name__ == "__main__":
    main()