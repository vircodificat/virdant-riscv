# crt0.S — bare-metal startup for Dhrystone on virdant-riscv.
#
# The bootloader has already copied the image to RAM at 0x80000000 and
# jumped to _start.  Set up gp and the stack, zero .bss (including
# .sbss — small globals — which the linker script places inside the
# zeroed range), run main, and exit through EBREAK with main's return
# value in a0 (the virt simulator's exit convention).

    .section .text.start
    .globl _start
_start:
.option push
.option norelax
    la      gp, __global_pointer$
.option pop
    la      sp, __stack_top

    # Zero .bss (the bootloader only copies file-backed bytes).
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main
    ebreak                  # a0 = main's return value = exit code
