#!/usr/bin/env python3
"""
instr_trace.py - Print the decoded RISC-V instruction (and its timestamp)
whenever `top.soc.cpu.instr` changes in a VCD trace.

Usage:
    vir run --cycles 10000 --trace        # writes trace.vcd
    python3 instr_trace.py [trace.vcd]
"""

import argparse
import signal
import sys

from vcd.reader import tokenize, TokenKind

INSTR_PATH = "top.soc.cpu.instr"


# --------------------------------------------------------------------- #
# RISC-V (RV32I + Zicsr) decoder
# --------------------------------------------------------------------- #

REG_NAMES = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

CSR_NAMES = {
    0x300: "mstatus", 0x301: "misa", 0x304: "mie", 0x305: "mtvec",
    0x340: "mscratch", 0x341: "mepc", 0x342: "mcause", 0x343: "mtval",
    0x344: "mip", 0xF11: "mvendorid", 0xF12: "marchid",
    0xF13: "mimpid", 0xF14: "mhartid",
}


def _reg(n: int) -> str:
    return REG_NAMES[n] if n < len(REG_NAMES) else f"x{n}"


def _sext(value: int, bits: int) -> int:
    if value & (1 << (bits - 1)):
        value -= 1 << bits
    return value


def decode(instr: int) -> str:
    """Decode a 32-bit instruction word into a mnemonic string."""
    opcode = instr & 0x7F
    rd = (instr >> 7) & 0x1F
    funct3 = (instr >> 12) & 0x7
    rs1 = (instr >> 15) & 0x1F
    rs2 = (instr >> 20) & 0x1F
    funct7 = (instr >> 25) & 0x7F
    funct12 = (instr >> 20) & 0xFFF

    if opcode == 0x37:  # LUI
        return f"LUI {_reg(rd)}, 0x{instr >> 12:05x}"
    if opcode == 0x17:  # AUIPC
        return f"AUIPC {_reg(rd)}, 0x{instr >> 12:05x}"
    if opcode == 0x6F:  # JAL
        imm = _sext(((instr >> 31) & 0x1) << 20
                    | ((instr >> 12) & 0xFF) << 12
                    | ((instr >> 20) & 0x1) << 11
                    | ((instr >> 21) & 0x3FF) << 1, 21)
        return f"JAL {_reg(rd)}, {imm:+d}"
    if opcode == 0x67:  # JALR
        imm = _sext(instr >> 20, 12)
        return f"JALR {_reg(rd)}, {imm:+d}({_reg(rs1)})"
    if opcode == 0x63:  # BRANCH
        imm = _sext(((instr >> 31) & 0x1) << 12
                    | ((instr >> 7) & 0x1) << 11
                    | ((instr >> 25) & 0x3F) << 5
                    | ((instr >> 8) & 0xF) << 1, 13)
        mnem = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE",
                6: "BLTU", 7: "BGEU"}.get(funct3)
        if mnem:
            return f"{mnem} {_reg(rs1)}, {_reg(rs2)}, {imm:+d}"
    if opcode == 0x03:  # LOAD
        imm = _sext(instr >> 20, 12)
        mnem = {0: "LB", 1: "LH", 2: "LW", 4: "LBU", 5: "LHU"}.get(funct3)
        if mnem:
            return f"{mnem} {_reg(rd)}, {imm:+d}({_reg(rs1)})"
    if opcode == 0x23:  # STORE
        imm = _sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        mnem = {0: "SB", 1: "SH", 2: "SW"}.get(funct3)
        if mnem:
            return f"{mnem} {_reg(rs2)}, {imm:+d}({_reg(rs1)})"
    if opcode == 0x13:  # OP-IMM
        imm = _sext(instr >> 20, 12)
        if funct3 == 0:
            return f"ADDI {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 2:
            return f"SLTI {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 3:
            return f"SLTIU {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 4:
            return f"XORI {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 6:
            return f"ORI {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 7:
            return f"ANDI {_reg(rd)}, {_reg(rs1)}, {imm:+d}"
        if funct3 == 1:  # SLLI
            return f"SLLI {_reg(rd)}, {_reg(rs1)}, {rs2}"
        if funct3 == 5:  # SRLI / SRAI
            mnem = "SRAI" if funct7 & 0x20 else "SRLI"
            return f"{mnem} {_reg(rd)}, {_reg(rs1)}, {rs2}"
    if opcode == 0x33:  # OP
        if funct7 & 0x20 and funct7 != 0x20:  # only SUB (0x20) is M-extension-free
            pass
        mnem = {
            (0, 0x00): "ADD", (0, 0x20): "SUB",
            (1, 0x00): "SLL", (2, 0x00): "SLT", (3, 0x00): "SLTU",
            (4, 0x00): "XOR", (5, 0x00): "SRL", (5, 0x20): "SRA",
            (6, 0x00): "OR", (7, 0x00): "AND",
        }.get((funct3, funct7))
        if mnem:
            return f"{mnem} {_reg(rd)}, {_reg(rs1)}, {_reg(rs2)}"
    if opcode == 0x0F:  # FENCE
        if funct3 == 0:
            return "FENCE"
        if funct3 == 1:
            return "FENCE.I"
    if opcode == 0x73:  # SYSTEM
        if funct3 == 0:
            return {0x000: "ECALL", 0x001: "EBREAK",
                    0x302: "MRET", 0x105: "WFI"}.get(funct12, "SYSTEM")
        csr = CSR_NAMES.get(funct12, f"0x{funct12:03x}")
        if funct3 in (1, 2, 3):
            mnem = {1: "CSRRW", 2: "CSRRS", 3: "CSRRC"}[funct3]
            return f"{mnem} {_reg(rd)}, {csr}, {_reg(rs1)}"
        if funct3 in (5, 6, 7):
            mnem = {5: "CSRRWI", 6: "CSRRSI", 7: "CSRRCI"}[funct3]
            return f"{mnem} {_reg(rd)}, {csr}, 0x{rs1:x}"
    return f"UNKNOWN (0x{instr:08x})"


# --------------------------------------------------------------------- #
# VCD walking
# --------------------------------------------------------------------- #

def main():
    parser = argparse.ArgumentParser(
        description="Print decoded RISC-V instructions on changes of "
                    f"{INSTR_PATH}.")
    parser.add_argument("vcd", nargs="?", default="trace.vcd",
                        help="path to the VCD file (default: trace.vcd)")
    args = parser.parse_args()

    # Restore default SIGPIPE so piping to head(1) etc. doesn't crash.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    # ---- Phase 1: header, find the instr signal's id code ------------- #
    scope = []
    instr_id = None
    with open(args.vcd, "rb") as f:
        for tok in tokenize(f):
            if tok.kind == TokenKind.SCOPE:
                scope.append(tok.scope.ident)
            elif tok.kind == TokenKind.UPSCOPE:
                scope.pop()
            elif tok.kind == TokenKind.VAR:
                path = ".".join(scope + [tok.var.reference])
                if path == INSTR_PATH:
                    instr_id = tok.var.id_code
            elif tok.kind == TokenKind.ENDDEFINITIONS:
                break

    if instr_id is None:
        print(f"Error: could not find signal {INSTR_PATH!r} in {args.vcd}",
              file=sys.stderr)
        sys.exit(1)

    # ---- Phase 2: emit on every change of instr ----------------------- #
    prev = None
    timestamp = 0
    with open(args.vcd, "rb") as f:
        for tok in tokenize(f):
            if tok.kind == TokenKind.CHANGE_TIME:
                timestamp = tok.time_change
            elif tok.kind == TokenKind.CHANGE_VECTOR:
                if tok.vector_change.id_code == instr_id:
                    value = tok.vector_change.value
                    if value != prev:
                        prev = value
                        print(f"{timestamp:>12}  0x{value:08x}  "
                              f"{decode(int(value))}")


if __name__ == "__main__":
    main()
