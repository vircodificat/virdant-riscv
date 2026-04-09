#!/usr/bin/env python3
"""
run_riscv_tests.py

Enumerate all rv32ui-p-* ELF files in build/share/riscv-tests/isa/,
convert each to a $readmemh-compatible hex file (one 32-bit word per line)
in software-tests/, and report results.
"""

import os
import struct
import subprocess
import sys

ISA_DIR = "build/share/riscv-tests/isa"
OUT_DIR = "software-tests"

OBJCOPY = "riscv64-unknown-elf-objcopy"
ROM_WORDS = 1024  # must match `reg [31:0] mem[1024]` in ext/Mem.sv


def elf_to_hex(elf_path: str, hex_path: str) -> None:
    """
    Dump the .text.init and .tohost sections of an ELF to a flat binary
    (objcopy preserves the gap between them), then write one hex word per line.
    The ELFs are linked at 0x80000000 but are position-independent, so we
    treat the raw binary blob as starting at address 0.
    """
    # Extract the relevant sections as a flat binary blob.
    bin_path = hex_path + ".tmp.bin"
    try:
        subprocess.run(
            [
                OBJCOPY,
                "-O", "binary",
                "--only-section=.text.init",
                "--only-section=.tohost",
                elf_path,
                bin_path,
            ],
            check=True,
            capture_output=True,
        )

        with open(bin_path, "rb") as f:
            data = f.read()

        # Pad to a multiple of 4 bytes.
        rem = len(data) % 4
        if rem:
            data += b"\x00" * (4 - rem)

        words = [struct.unpack_from("<I", data, i)[0] for i in range(0, len(data), 4)]

        # Patch word 0: replace the jal to reset_vector with jal x0, 0x18c (test_2).
        # JAL x0, 0x18c encodes as 0x18c0006f.
        words[0] = 0x18c0006f

        if len(words) > ROM_WORDS:
            print(f"  WARNING: {os.path.basename(elf_path)}: binary is {len(words)} words "
                  f"(ROM holds {ROM_WORDS}); truncating — test may not run correctly.")
            words = words[:ROM_WORDS]

        with open(hex_path, "w") as f:
            for w in words:
                f.write(f"{w:08x}\n")

    finally:
        if os.path.exists(bin_path):
            os.remove(bin_path)


def main() -> None:
    if not os.path.isdir(ISA_DIR):
        print(f"Error: {ISA_DIR} not found. Run 'make build_tests' first.", file=sys.stderr)
        sys.exit(1)

    os.makedirs(OUT_DIR, exist_ok=True)

    # Enumerate ELF files (exclude .dump files).
    elfs = sorted(
        f for f in os.listdir(ISA_DIR)
        if not f.endswith(".dump")
    )

    if not elfs:
        print(f"No ELF files found in {ISA_DIR}.", file=sys.stderr)
        sys.exit(1)

    print(f"Converting {len(elfs)} ELF(s) to hex in {OUT_DIR}/")
    for name in elfs:
        elf_path = os.path.join(ISA_DIR, name)
        hex_path = os.path.join(OUT_DIR, name + ".hex")
        elf_to_hex(elf_path, hex_path)
        print(f"  {name} -> {hex_path}")

    print("Done.")


if __name__ == "__main__":
    main()
