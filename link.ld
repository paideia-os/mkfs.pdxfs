/* mkfs.pdxfs linker script (R64v2 satellite-linking closure, paideia-os
 * #1976). Mirrors paideia-os's src/user/true.ld: ENTRY(_start), text at
 * 0x00400000, data at 0x00600000, .bss contiguous with .data.
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x00400000;

    .text : ALIGN(4K) {
        KEEP(*(.text._start))
        *(.text .text.*)
    } :text

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    } :text

    . = 0x00600000;

    .data : ALIGN(4K) {
        *(.data .data.*)
    } :data

    /* .bss follows .data CONTIGUOUSLY -- no `. = 0x00700000;` here, and
     * there must not be one. See paideia-os's src/user/true.ld (R31.M2-1595
     * / #1595) for why: a fixed-address gap between .data and .bss stretches
     * the single `data` PT_LOAD across the hole, and the loader maps every
     * page of that hole. tools/verify-user-image-extent.sh (paideia-os)
     * fails the build if any PT_LOAD in a linked user image reacquires one.
     */
    .bss (NOLOAD) : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
        . = ALIGN(4K);
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame*)
        *(.note.*)
    }
}
