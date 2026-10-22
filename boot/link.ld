/* Link script for the virt flash bootloader.
 *
 * The bootloader executes in place from the emulated SPI flash at
 * 0x20000000 (the CPU reset address) and must fit in the first 0x1000
 * bytes of the flash image, before the test image embedded at 0x1000.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  flash (rx) : ORIGIN = 0x20000000, LENGTH = 0x1000
}

SECTIONS
{
  . = 0x20000000;

  .text : {
    *(.text.init)
    *(.text)
    *(.text.*)
  } > flash
}