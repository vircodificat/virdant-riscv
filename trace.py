#!/usr/bin/env python3
"""
trace.py - Read dump.vcd and print a trace of <ADDRESS> <INSTR>, one per line.

Each line corresponds to a positive clock edge (posedge), showing the
program counter and instruction word as hexadecimal values.
"""

import argparse
import os
import signal
import sys
from vcd.reader import tokenize, TokenKind


def main():
    parser = argparse.ArgumentParser(description="Print a trace and summary from a VCD dump.")
    parser.add_argument("vcd", nargs="?", default="dump.vcd",
                        help="path to dump.vcd (default: dump.vcd)")
    parser.add_argument("-s", "--summary", action="store_true",
                        help="only print the summary, omit the instruction trace")
    args = parser.parse_args()

    # Restore default SIGPIPE handling so piping to head(1) etc. doesn't crash.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    vcd_path = args.vcd

    # ------------------------------------------------------------------ #
    # Phase 1 – parse VCD header to build id_code -> signal path mapping
    # ------------------------------------------------------------------ #
    current_scope = []          # stack of scope identifiers
    pc_id = None
    instr_id = None
    clock_id = None
    cycle_id = None
    take_branch_id = None
    mem_stb_id = None
    mem_we_id = None

    with open(vcd_path, "rb") as f:
        for tok in tokenize(f):
            if tok.kind == TokenKind.SCOPE:
                current_scope.append(tok.scope.ident)
            elif tok.kind == TokenKind.UPSCOPE:
                current_scope.pop()
            elif tok.kind == TokenKind.VAR:
                full_path = ".".join(current_scope + [tok.var.reference])
                if full_path == "TOP.Top.cpu.pc":
                    pc_id = tok.var.id_code
                elif full_path == "TOP.Top.cpu.instr":
                    instr_id = tok.var.id_code
                elif full_path == "TOP.Top.cpu.clock":
                    clock_id = tok.var.id_code
                elif full_path == "TOP.Top.cycle":
                    cycle_id = tok.var.id_code
                elif full_path == "TOP.Top.cpu.control.take_branch":
                    take_branch_id = tok.var.id_code
                elif full_path == "TOP.Top.cpu.mem.stb":
                    mem_stb_id = tok.var.id_code
                elif full_path == "TOP.Top.cpu.mem.we":
                    mem_we_id = tok.var.id_code
            elif tok.kind == TokenKind.ENDDEFINITIONS:
                break

    if not all([pc_id, instr_id, clock_id]):
        print("Error: could not find all required signals (pc, instr, clock)",
              file=sys.stderr)
        sys.exit(1)

    # ------------------------------------------------------------------ #
    # Phase 2 – iterate value changes and emit trace on every posedge
    # ------------------------------------------------------------------ #
    pc_val = 0
    instr_val = 0
    clock_val = 0       # previous clock value (0 or 1)
    cycle_val = 0
    take_branch_val = 0
    mem_stb_val = 0
    mem_we_val = 0
    branch_taken_count = 0
    mem_access_count = 0
    mem_write_count = 0
    instr_seen = set()

    with open(vcd_path, "rb") as f:
        for tok in tokenize(f):
            if tok.kind == TokenKind.CHANGE_SCALAR:
                sc = tok.scalar_change
                if sc.id_code == clock_id:
                    new_val = 1 if sc.value == "1" else 0
                    if clock_val == 0 and new_val == 1:
                        # posedge – emit current pc and instruction
                        if not args.summary:
                            print(f"{pc_val:08x} {instr_val:08x}")
                    clock_val = new_val
                elif sc.id_code == take_branch_id:
                    new_val = 1 if sc.value == "1" else 0
                    if take_branch_val == 0 and new_val == 1:
                        branch_taken_count += 1
                    take_branch_val = new_val
                elif sc.id_code == mem_stb_id:
                    new_val = 1 if sc.value == "1" else 0
                    if mem_stb_val == 0 and new_val == 1:
                        mem_access_count += 1
                    mem_stb_val = new_val
                elif sc.id_code == mem_we_id:
                    new_val = 1 if sc.value == "1" else 0
                    if mem_we_val == 0 and new_val == 1:
                        mem_write_count += 1
                    mem_we_val = new_val

            elif tok.kind == TokenKind.CHANGE_VECTOR:
                cv = tok.vector_change
                if cv.id_code == pc_id:
                    pc_val = cv.value
                elif cv.id_code == instr_id:
                    instr_val = cv.value
                    instr_seen.add(cv.value)
                elif cv.id_code == cycle_id:
                    cycle_val = cv.value

    # ------------------------------------------------------------------ #
    # Phase 3 – print summary
    # ------------------------------------------------------------------ #
    print(f"total cycles: {cycle_val}")
    print(f"branches taken: {branch_taken_count}")
    print(f"total unique instructions: {len(instr_seen)}")
    print(f"total memory accesses: {mem_access_count}")
    print(f"total memory writes: {mem_write_count}")


if __name__ == "__main__":
    main()