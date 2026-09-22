/*
 * The ICU locale data, as the symbol `libicuuc` resolves its common data
 * through. ICU's own build embeds the same bytes with its `genccode` tool; the
 * assembler does it here without a tool of our own. The build passes
 * ICU_DATA_SYMBOL and ICU_DATA_FILE as defines.
 */
    .section .note.GNU-stack,"",%progbits
    .section .rodata
    .globl ICU_DATA_SYMBOL
    .type ICU_DATA_SYMBOL, %object
    .balign 16
ICU_DATA_SYMBOL:
    .incbin ICU_DATA_FILE
    .size ICU_DATA_SYMBOL, . - ICU_DATA_SYMBOL
