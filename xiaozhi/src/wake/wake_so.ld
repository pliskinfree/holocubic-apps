SECTIONS
{
  .data.rel.ro :
  {
    *(.data.rel.ro)
    *(.data.rel.ro.*)
  }

  .data :
  {
    *(.data.esp_sr_*)
    *(.data.esp_fbank_f32)
    *(.data.esp_fbank_s16)
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

  /*
   * Keep ESP-SR .iram1 hot code in the same loadable .text image.
   * Some ESP-SR objects contain fixed Xtensa call8 edges from .text to .iram1.
   * The runtime ELF loader relocates data-held function pointers, but it does
   * not rewrite those already-linked relative call instructions. A separate
   * .mod_iram output section can therefore make code jump to text_base +
   * .mod_iram_vaddr instead of the copied IRAM block, ending in
   * IllegalInstruction. Merging .iram1* into .text keeps those direct calls
   * inside one contiguous executable section.
   */
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
