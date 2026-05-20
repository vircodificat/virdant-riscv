#!/usr/bin/env python3
"""
Test scoreboard for RISC-V ISA tests (rv32i).
Runs each test with ./build/sim and reports PASS, FAIL, or TIMEOUT.
"""

import os
import subprocess
import sys
from pathlib import Path
from collections import namedtuple

TestResult = namedtuple('TestResult', ['name', 'status'])

def run_test(test_path, timeout=3):
    """
    Run a single test with the simulator.
    Returns 'PASS', 'FAIL', or 'TIMEOUT'.
    """
    try:
        result = subprocess.run(
            ['./build/sim', test_path],
            cwd=os.getcwd(),
            capture_output=True,
            timeout=timeout,
            text=True
        )
        if result.returncode == 0:
            return 'PASS'
        else:
            return 'FAIL'
    except subprocess.TimeoutExpired:
        return 'TIMEOUT'
    except Exception as e:
        print(f"Error running {test_path}: {e}", file=sys.stderr)
        return 'FAIL'

def main():
    # Find all rv32ui-p-* tests
    isa_dir = Path('riscv-tests/isa')
    if not isa_dir.exists():
        print("Error: riscv-tests/isa directory not found", file=sys.stderr)
        sys.exit(1)

    # Get all rv32ui-p-* test files (exclude .dump files)
    test_files = sorted([
        f for f in isa_dir.glob('rv32ui-p-*')
        if f.is_file() and not f.name.endswith('.dump')
    ])

    if not test_files:
        print("Error: No rv32i tests found", file=sys.stderr)
        sys.exit(1)

    # Find the longest test name for alignment
    max_name_len = max(len(f.name) for f in test_files)

    results = []
    for test_file in test_files:
        test_name = test_file.name
        # Print test name as it starts, with padding
        print(f"{test_name:<{max_name_len}}  ", end='', flush=True)
        status = run_test(str(test_file))
        # Print result on the same line
        if status == 'PASS':
            print("\033[32mPASS\033[0m")
        elif status == 'FAIL':
            print("\033[31mFAIL\033[0m")
        elif status == 'TIMEOUT':
            print("\033[33mTIMEOUT\033[0m")
        else:
            raise Exception

        results.append(TestResult(test_name, status))

    # Calculate and print pass rate
    pass_count = sum(1 for r in results if r.status == 'PASS')
    total_count = len(results)
    pass_rate = (pass_count / total_count * 100) if total_count > 0 else 0

    print()
    print(f"Pass Rate: {pass_count}/{total_count} ({pass_rate:.1f}%)")

if __name__ == '__main__':
    main()
