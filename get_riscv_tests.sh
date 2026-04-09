#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(realpath .)"

# Clone only if the directory doesn't already exist.
if [ ! -d riscv-tests ]; then
    git clone https://github.com/riscv/riscv-tests
fi

cd riscv-tests
git submodule update --init --recursive
autoconf
./configure --prefix="$PROJECT_ROOT/build"

# Patch the generated top-level Makefile:
#   - remove benchmarks from the default build and install
#   - point install at the project's build/ directory (already set via --prefix)
sed -i \
    -e 's/^all: benchmarks isa/all: isa/' \
    -e '/install.*benchmarks/d' \
    -e '/find benchmarks/d' \
    -e '/^benchmarks:/d' \
    -e '/\$(MAKE).*-C benchmarks/d' \
    -e '/mkdir -p benchmarks/d' \
    -e '/|| \$(MAKE).*benchmarks/d' \
    -e 's/ benchmarks//' \
    Makefile

# Patch isa/Makefile to restrict the test list to rv32ui-p-* only.
# The filter is inserted just before tests_dump is defined, after all
# Makefrags have been included and appended to $(tests).
sed -i '/^tests_dump/i tests := $(filter rv32ui-p-%,$(tests))' isa/Makefile

# Build and install.
make install XLEN=32
