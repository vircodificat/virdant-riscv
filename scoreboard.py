#!/usr/bin/env python3
"""
Test scoreboard for RISC-V ISA tests (rv32i), run on the virt simulator.

Each test ELF is converted to a SPI flash image (XIP bootloader at offset
0x1000-by-elf2flash.py --boot, test image at flash 0x1000) and executed by
`./build/Top` (the virt::Virt simulator built by `virt build`).  The tests
report their result with the riscv-tests exit convention (`a7=93;
a0=<code>; ecall`), which the SoC forwards through the platform's `exit`
port: the simulator exits with code a0.

  exit code 0      -> PASS
  exit code 124    -> TIMEOUT (hit the --cycles cap: the CPU hung)
  anything else    -> FAIL (a0 carries the encoded failing test number)
"""

import argparse
import subprocess
import sys
from pathlib import Path
from collections import namedtuple

TestResult = namedtuple('TestResult', ['name', 'status'])

# Flash read budget: one boot copy (~2M cycles over SPI) plus the test
# itself running from RAM.  The simulator exits early on the tests' ecall.
CYCLES = 20_000_000
TIMEOUT = 300  # seconds (wall) per test


def run_test(test_path, vcd_path=None, timeout=TIMEOUT):
    """Run a single test on the virt simulator. Returns PASS/FAIL/TIMEOUT.

    When *vcd_path* is set, the simulator writes a VCD trace to that file.
    """
    name = Path(test_path).stem
    flash = Path("build") / f"{name}.flash"
    try:
        subprocess.run(
            ["./elf2flash.py", str(test_path), "--boot", "build/boot.bin",
             "-o", str(flash)],
            check=True, capture_output=True,
        )
        cmd = ["vir", "run", "--flash", str(flash), "--fps-no-cap", "--cycles", str(CYCLES)]
        if vcd_path is not None:
            cmd += ["--vcd", str(vcd_path), "--trace"]
        result = subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=timeout,
        )
        rc = result.returncode
        if rc == 0:
            return 'PASS'
        if rc == 124:
            return 'TIMEOUT'
        return 'FAIL'
    except subprocess.TimeoutExpired:
        return 'TIMEOUT'
    except Exception as e:
        print(f"Error running {test_path}: {e}", file=sys.stderr)
        return 'FAIL'


def main():
    parser = argparse.ArgumentParser(
        description="Run RISC-V ISA tests on the virt simulator.")
    parser.add_argument("--trace", action="store_true",
                        help="Write a .vcd trace for each test under build/")
    args = parser.parse_args()

    # Find all rv32ui-p-* tests
    isa_dir = Path('riscv-tests/isa')
    if not isa_dir.exists():
        print("Error: riscv-tests/isa directory not found", file=sys.stderr)
        sys.exit(1)

    test_files = sorted([
        f for f in isa_dir.glob('rv32ui-p-*')
        if f.is_file() and not f.name.endswith('.dump')
    ])

    if not test_files:
        print("Error: No rv32i tests found", file=sys.stderr)
        sys.exit(1)

    max_name_len = max(len(f.name) for f in test_files)

    build_dir = Path("build")
    build_dir.mkdir(exist_ok=True)

    results = []
    for test_file in test_files:
        test_name = test_file.name
        print(f"{test_name:<{max_name_len}}  ", end='', flush=True)

        vcd_path = (build_dir / f"{test_name}.vcd") if args.trace else None
        status = run_test(test_file, vcd_path=vcd_path)

        if status == 'PASS':
            print("\033[32mPASS\033[0m")
        elif status == 'FAIL':
            print("\033[31mFAIL\033[0m")
        elif status == 'TIMEOUT':
            print("\033[33mTIMEOUT\033[0m")
        else:
            raise Exception

        if vcd_path and vcd_path.exists():
            print(f"  trace: {vcd_path}")

        results.append(TestResult(test_name, status))

    pass_count = sum(1 for r in results if r.status == 'PASS')
    total_count = len(results)
    pass_rate = (pass_count / total_count * 100) if total_count > 0 else 0

    print()
    print(f"Pass Rate: {pass_count}/{total_count} ({pass_rate:.1f}%)")


if __name__ == '__main__':
    main()
