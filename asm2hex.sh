#!/usr/bin/env bash
# asm2hex.sh - Assemble a RISC-V (rv32i) source file and produce a $readmemh-
#              compatible hex file padded to 1024 x 32-bit words.
#
# Usage: ./asm2hex.sh <input.s> [output.hex]
#   input.s     - RISC-V assembly source file
#   output.hex  - destination hex file (default: rom.hex)

set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-rom.hex}"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 <input.s> [output.hex]" >&2
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo "Error: file not found: $INPUT" >&2
    exit 1
fi

GCC="riscv64-unknown-elf-gcc"
OBJCOPY="riscv64-unknown-elf-objcopy"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

ELF="$TMPDIR_WORK/out.elf"
BIN="$TMPDIR_WORK/out.bin"

# Assemble + link: rv32i, bare-metal, text at address 0
"$GCC" \
    -march=rv32i \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -Wl,-Ttext=0x0,-e0 \
    -o "$ELF" \
    "$INPUT"

# Extract raw binary of the .text section only
"$OBJCOPY" -O binary --only-section=.text "$ELF" "$BIN"

# Convert binary to $readmemh hex (1024 words, padded with 00000000)
python3 - "$BIN" "$OUTPUT" <<'EOF'
import sys, struct

binfile, outfile = sys.argv[1], sys.argv[2]
ROM_WORDS = 1024

with open(binfile, 'rb') as f:
    data = f.read()

# Pad binary to a multiple of 4 bytes
remainder = len(data) % 4
if remainder:
    data += b'\x00' * (4 - remainder)

words = [struct.unpack_from('<I', data, i)[0] for i in range(0, len(data), 4)]

if len(words) > ROM_WORDS:
    print(f"Warning: program is {len(words)} words, truncating to {ROM_WORDS}", file=sys.stderr)
    words = words[:ROM_WORDS]

# Pad to exactly 1024 words
words += [0] * (ROM_WORDS - len(words))

with open(outfile, 'w') as f:
    for w in words:
        f.write(f'{w:08x}\n')

print(f"Wrote {ROM_WORDS} words to {outfile} ({len([w for w in words if w != 0])} non-zero)")
EOF
