#!/usr/bin/env python3
"""elf2flash — convert a RISC-V ELF into a SPI flash image for the virt sim.

The virt harness (`virdant-virt`) loads a 16 MiB SPI flash image and serves
it over the emulated flash device (0x03 READ).  This script shifts each ELF
PT_LOAD segment down by the RAM base so that virtual address 0x8000_0000
lands at flash offset 0, preserving the segment layout: file bytes go at
`vaddr - ram_base`, and gaps between segments stay erased (0xFF).

Usage:
    ./elf2flash.py sw/uart_demo/echo.elf -o echo.flash
    ./elf2flash.py program.elf --ram-base 0x80000000 --size 0x1000000

Notes:
  * Only file-backed bytes (p_filesz) are stored; flash cannot carry
    uninitialized data, so any BSS (p_memsz > p_filesz) must be zeroed by
    the program at runtime.
  * Segments that do not fall inside the RAM window are skipped with a note.
"""

import argparse
import struct
import sys

PT_LOAD = 1

# ELF32 header field offsets.
E_PHOFF = 0x1C
E_PHENTSIZE = 0x2A
E_PHNUM = 0x2C

# Elf32_Phdr layout: type, offset, vaddr, paddr, filesz, memsz, flags, align.
PHDR_FMT = "<IIIIIIII"
PHDR_SIZE = 32


def fail(msg: str) -> None:
    print(f"elf2flash: error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_phdrs(data: bytes) -> list[dict]:
    if len(data) < 0x34:
        fail("file too small to be an ELF")
    if data[:4] != b"\x7fELF":
        fail("not an ELF file (bad magic)")
    if data[4] != 1:
        fail("not a 32-bit ELF (EI_CLASS != ELFCLASS32)")
    if data[5] != 1:
        fail("not little-endian (EI_DATA != ELFDATA2LSB)")

    phoff = struct.unpack_from("<I", data, E_PHOFF)[0]
    phentsize = struct.unpack_from("<H", data, E_PHENTSIZE)[0]
    phnum = struct.unpack_from("<H", data, E_PHNUM)[0]
    if phnum == 0:
        fail("ELF has no program headers")
    if phentsize < PHDR_SIZE:
        fail(f"unexpected phentsize {phentsize}")

    phdrs = []
    for i in range(phnum):
        off = phoff + i * phentsize
        if off + PHDR_SIZE > len(data):
            fail(f"program header {i} out of bounds")
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = (
            struct.unpack_from(PHDR_FMT, data, off)
        )
        phdrs.append(
            {
                "index": i,
                "type": p_type,
                "offset": p_offset,
                "vaddr": p_vaddr,
                "paddr": p_paddr,
                "filesz": p_filesz,
                "memsz": p_memsz,
                "flags": p_flags,
            }
        )
    return phdrs


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Convert a RISC-V ELF into a SPI flash image (.flash)."
    )
    ap.add_argument("elf", help="input ELF file")
    ap.add_argument("-o", "--output", help="output flash image (default: <elf>.flash)")
    ap.add_argument(
        "--ram-base",
        type=lambda s: int(s, 0),
        default=0x80000000,
        help="virtual address that maps to flash offset 0 (default 0x80000000)",
    )
    ap.add_argument(
        "--size",
        type=lambda s: int(s, 0),
        default=1 << 24,
        help="flash image size in bytes (default 16 MiB)",
    )
    ap.add_argument(
        "--fill",
        type=lambda s: int(s, 0),
        default=0xFF,
        help="fill byte for gaps between segments (default 0xFF, erased flash)",
    )
    ap.add_argument(
        "--boot",
        help="raw binary placed at flash offset 0 (e.g. the XIP bootloader); "
        "the ELF image is then placed at --image-offset",
    )
    ap.add_argument(
        "--image-offset",
        type=lambda s: int(s, 0),
        default=None,
        help="flash offset of the ELF image (default 0x1000 when --boot is "
        "given, else 0)",
    )
    args = ap.parse_args()

    image_offset = args.image_offset
    if image_offset is None:
        image_offset = 0x1000 if args.boot else 0

    if args.boot:
        with open(args.boot, "rb") as f:
            boot = f.read()
        if len(boot) > image_offset:
            fail(
                f"bootloader {args.boot} is {len(boot)} bytes, larger than the "
                f"image offset 0x{image_offset:x}"
            )

    out_path = args.output or args.elf + ".flash"

    with open(args.elf, "rb") as f:
        data = f.read()
    phdrs = parse_phdrs(data)

    image = bytearray([args.fill & 0xFF] * args.size)
    written: list[tuple[int, int, dict]] = []  # (start, end, phdr)

    for ph in phdrs:
        if ph["type"] != PT_LOAD:
            continue
        if ph["filesz"] == 0:
            if ph["memsz"] > 0:
                print(
                    f"note: segment {ph['index']} is BSS-only "
                    f"(vaddr 0x{ph['vaddr']:08x}, memsz 0x{ph['memsz']:x}); "
                    "it must be zeroed at runtime"
                )
            continue

        rel = ph["vaddr"] - args.ram_base
        skip = 0
        if rel < 0:
            # The linker may page-align the segment vaddr below the RAM
            # base (e.g. a segment at 0x7ffff000 covering .text at
            # 0x80000000).  Clamp: skip the part outside the RAM window.
            skip = -rel
            rel = 0
        dest = image_offset + rel
        length = ph["filesz"] - skip
        if length <= 0:
            print(
                f"note: skipping segment {ph['index']} "
                f"(vaddr 0x{ph['vaddr']:08x} entirely below RAM base "
                f"0x{args.ram_base:08x})"
            )
            continue
        if dest + length > args.size:
            fail(
                f"segment {ph['index']} (vaddr 0x{ph['vaddr']:08x}, "
                f"filesz 0x{ph['filesz']:x}) overflows the {args.size:#x}-byte flash image"
            )
        if ph["offset"] + ph["filesz"] > len(data):
            fail(f"segment {ph['index']} file bytes out of bounds")

        # Overlap check against already-placed segments.
        for start, end, other in written:
            if dest < end and start < dest + ph["filesz"]:
                fail(
                    f"segment {ph['index']} (vaddr 0x{ph['vaddr']:08x}) overlaps "
                    f"segment {other['index']} (vaddr 0x{other['vaddr']:08x})"
                )

        image[dest : dest + length] = data[
            ph["offset"] + skip : ph["offset"] + ph["filesz"]
        ]
        written.append((dest, dest + length, ph))

        bss = ph["memsz"] - ph["filesz"]
        bss_note = f", bss 0x{bss:x} at runtime" if bss > 0 else ""
        clamp_note = f" (clamped {skip} bytes below RAM base)" if skip > 0 else ""
        print(
            f"segment {ph['index']}: vaddr 0x{ph['vaddr']:08x} "
            f"-> flash 0x{dest:06x}, {length} bytes{clamp_note}{bss_note}"
        )

    if not written:
        fail("no loadable segments placed")

    if args.boot:
        image[0 : len(boot)] = boot

    with open(out_path, "wb") as f:
        f.write(image)
    print(f"wrote {args.size} bytes to {out_path}")


if __name__ == "__main__":
    main()