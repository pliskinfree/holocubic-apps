SECTIONS
{
  .data.rel.ro :
  {
    *(.data.rel.ro)
    *(.data.rel.ro.*)
  }

  .data :
  {
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    *(.got)
    *(.got.*)
  }

  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
  }

  .bss (NOLOAD) :
  {
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
  }

  .text :
  {
    *(.iram1.literal)
    *(.iram1.literal.*)
    *(.iram1)
    *(.iram1.*)
    *(.literal)
    *(.literal.*)
    *(.text)
    *(.text.*)
    *(.stub)
    *(.gnu.warning)
    *(.gnu.linkonce.literal.*)
    *(.gnu.linkonce.t.*.literal)
    *(.gnu.linkonce.t.*)
    *(.plt)
    *(.plt.*)
  }
}
