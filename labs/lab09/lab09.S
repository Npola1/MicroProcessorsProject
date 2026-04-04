.syntax unified
.cpu    cortex-m0plus
.thumb
.global main_asm
.align 4

@ Entry point to the ASM portion of the program
main_asm:
    bl      main_asm


.data
    .align 4