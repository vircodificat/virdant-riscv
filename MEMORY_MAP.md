# Memory Map - RISC-V ISA Test Programs

This document describes the memory layout implied by the ELF program headers of the test binaries in `riscv-tests/isa/`.

## Overview

All analyzed test programs follow a consistent memory layout pattern across different test cases. The memory organization uses three distinct segments (LOAD segments) plus one additional segment (0x70000003 type).

## Memory Regions

### Region 1: Read-Only Data Segment
- **Virtual Address**: `0x00000000`
- **Physical Address**: `0x00000000`
- **Size**: `0x63` bytes (99 bytes)
- **Flags**: `r--` (Read-only)
- **Alignment**: `2**0` (1-byte)
- **Purpose**: Non-loadable segment (likely symbol table or debug info)

### Region 2: Code Segment (Executable)
- **Virtual Address**: `0x80000000`
- **Physical Address**: `0x80000000`
- **Alignment**: `2**12` (4KB pages)
- **Flags**: `r-x` (Read + Execute)
- **Size Range**: `0x1BC - 0x103C` bytes (varies by test)
- **Purpose**: Contains executable instructions
- **Note**: This is the main instruction memory, mapped to 0x80000000 (typical for embedded/privileged code)

### Region 3: Data/BSS Segment (Readable/Writable)
- **Base Virtual Address**: `0x80001000` or `0x80002000`
- **Base Physical Address**: `0x80001000` or `0x80002000`
- **Alignment**: `2**12` (4KB pages)
- **Flags**: `rw-` (Read + Write)
- **Size Range**: `0x48 - 0x1180` bytes (varies by test)
- **Purpose**: Contains initialized and uninitialized data
- **Note**: Data segment follows immediately after code in 4KB-aligned page boundaries

## Address Space Layout

```
0x00000000 +---------+ 4 bytes
           | RO Data |
           | (0x63)  |
0x00000063 +---------+
           |  Unused |
0x80000000 +---------+ (4KB aligned)
           |  CODE   | (varies, typically 0.2-4 KB)
0x80000XXX +---------+ (4KB aligned)
           |  DATA   | (varies, typically 0.07-4.4 KB)
0x8000XXXX +---------+
```

## Segment Statistics

### Code Segment (r-x) Sizes
- **Minimum**: `0x1BC` bytes (example: simple)
- **Maximum**: `0x103C` bytes (example: ld_st)
- **Most Common**: `0x2XX - 0x7XX` bytes range

### Data Segment (rw-) Sizes
- **Minimum**: `0x48` bytes (most tests)
- **Maximum**: `0x1180` bytes (example: ma_data)
- **Most Common**: `0x48` or `0x1010-0x1050` bytes

## Key Observations

1. **Consistent Address Layout**: All binaries use the same base addresses (`0x80000000` for code, `0x80001000`/`0x80002000` for data)
2. **Page-Aligned Segments**: All segments are aligned to 4KB (2**12) page boundaries, indicating platform design for virtual memory systems
3. **Non-loadable Segment**: The first segment (type 0x70000003) is present in all binaries but marked as non-loadable
4. **Variable Code Size**: Different test programs have significantly different code sizes reflecting their complexity
5. **Variable Data Size**: Some tests (memory-related: `ld_st`, `lb`, `lbu`, `lh`, `lhu`, `lw`, `sb`, `sh`, `st_ld`, `ma_data`) require more data space for test patterns

## Test Category Memory Usage

### Small Data Tests (0x48 bytes)
Simple arithmetic and logic operations with minimal data requirements:
- add, addi, and, andi, auipc, beq, bge, bgeu, blt, bltu, bne, jal, jalr, lui, ori, sll, slli, slti, sltiu, sltu, sra, srai, srl, srli, sub, xor, xori

### Extended Data Tests (0x1000+ bytes)
Tests requiring larger data patterns for memory operations:
- ld_st (0x1050 bytes)
- lb, lbu, lh, lhu, lw (0x1010 bytes)
- sb, sh, st_ld, sw (0x1030-0x1050 bytes)
- ma_data (0x1180 bytes)

### Special Cases
- **fence_i**: Code size 0x294 (includes fence instruction), data 0x1020
