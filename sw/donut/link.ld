OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
  . = 0x80000000;

  .text : {
    *(.text.start)
    *(.text)
    *(.text.*)
  } > ram

  . = ALIGN(4);

  .rodata : {
    *(.rodata)
    *(.rodata.*)
  } > ram

  . = ALIGN(4);

  .data : {
    *(.data)
    *(.data.*)
  } > ram

  . = ALIGN(4);

  .bss : {
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    __bss_end = .;
  } > ram

  . = ALIGN(16);

  /* Reserve 4 KiB for the stack */
  . += 4096;
  __stack_top = .;

  _end = .;
}
