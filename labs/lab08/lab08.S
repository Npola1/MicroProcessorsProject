#include "hardware/regs/addressmap.h"
#include "hardware/regs/m0plus.h"

.syntax unified @ Use unified ARM assembly syntax
.cpu cortex-m0plus @ Target the Cortex M0+ processor
.thumb @ Use Thumb instruction mode for the RP2040
.global main_asm @ Expose the program entry label to the linker
.align 4 @ Align code on a 4-byte boundary

.equ SLEEP_TIME, 500 @ Set the delay duration in milliseconds
.equ LED_GPIO_PIN, 25 @ Define the GPIO pin used by the LED
.equ LED_GPIO_OUT, 1 @ Define the GPIO direction as output
.equ LED_VALUE_ON, 1 @ Define the output value for LED on
.equ LED_VALUE_OFF, 0 @ Define the output value for LED off
.equ SVC_ISR_OFFSET, 0x2C @ SVC corresponds to vector table entry 11
.equ SVC_MAX_INSTRS, 0x01 @ Highest valid SVC subroutine number


@ Main entry label for the assembly code
main_asm:
    bl init_gpio_led @ Set up the LED GPIO pin
    bl install_svc_isr @ Register the SVC interrupt handler


loop:
    svc #0 @ Trigger SVC handler 0 to switch the LED on
    nop @ Insert a no-operation after the SVC instruction
    bl do_sleep @ Wait briefly before continuing
    svc #1 @ Trigger SVC handler 1 to switch the LED off
    nop @ Insert a no-operation after the SVC instruction
    bl do_sleep @ Wait briefly before continuing
    b loop @ Branch back to repeat the loop forever



@ Subroutine that creates a short delay in the program
do_sleep:
@<TODO – add assembly code to implement the sleep delay using sleep_ms>
    push {lr}
    ldr r0, =SLEEP_TIME     @ Load the delay value of 500 ms, using ldr because movs cannot hold it
    bl sleep_ms
    pop {pc}               @ Restore the return address and go back to the caller


@ Subroutine that configures the built-in Pi Pico LED
init_gpio_led:
@<TODO – add assembly code to initialise the LED GPIO pin>
    push {lr}               @ Preserve the return address on the stack
    movs r0, #LED_GPIO_PIN  @ Put GPIO pin 25 into the first argument register
    bl asm_gpio_init        @ Call gpio_init to prepare the pin
    movs r0, #LED_GPIO_PIN  @ Load the pin number again as the first argument
    movs r1, #LED_GPIO_OUT  @ Put the output direction value into the second argument register
    bl asm_gpio_set_dir     @ Call gpio_set_dir to make the pin an output
    pop {pc}                @ Restore the return address and return


@ Subroutine that installs the SVC interrupt handler
install_svc_isr:
    ldr r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET) @ Load the address of the Vector Table Offset Register into r2
    ldr r1, [r2]                             @ Read the vector table base address from VTOR into r1
    movs r2, #SVC_ISR_OFFSET                 @ Load the offset for the SVC entry, which is 0x2C
    add r2, r1                               @ Combine the base address and offset to locate the SVC vector slot
    ldr r0, =svc_isr                         @ Load the address of this program's SVC handler into r0
    str r0, [r2]                             @ Store that handler address into the SVC slot
    bx lr                                    @ Return to the caller



@ Interrupt service routine for handling SVC calls
.thumb_func @ Needed for every interrupt service routine
svc_isr:
    push {lr}            @ Save the link register before branching to other routines
    ldr r0, [sp, #0x1C]  @ Load the saved PC from the exception stack frame at sp+0x1C
    subs r0, #0x2        @ Move back 2 bytes so r0 points to the SVC instruction itself
    ldr r0, [r0]         @ Read the SVC instruction from memory
    ldr r1, =#0xFF       @ Load a mask for extracting the lower 8-bit immediate value
    ands r0, r1          @ Apply the mask to get the SVC number only
    cmp r0, #SVC_MAX_INSTRS @ Check whether the SVC number is within the valid range
    bgt svc_done         @ If the number is invalid, skip handling and finish
    adr r1, svc_jmptbl   @ Load the address of the jump table relative to the current PC
    lsls r0, #2          @ Multiply the SVC number by 4 since each table entry is 4 bytes
    ldr r1, [r1, r0]     @ Fetch the target handler address from the jump table
    mov pc, r1           @ Branch to the chosen SVC handler
svc_done:
    pop {pc}             @ Restore the saved return address into PC and return from the exception



@ First SVC subroutine, switches the LED on
svc_num0:
    movs r0, #LED_GPIO_PIN  @ Load the GPIO pin number into the first argument register
    movs r1, #LED_VALUE_ON  @ Load the ON value, 1, into the second argument register
    bl asm_gpio_put         @ Call gpio_put to drive the LED on
    b svc_done @ Return to the main SVC handler when finished

@ Second SVC subroutine, switches the LED off
svc_num1:
    movs r0, #LED_GPIO_PIN  @ Load the GPIO pin number into the first argument register
    movs r1, #LED_VALUE_OFF @ Load the OFF value, 0, into the second argument register
    bl asm_gpio_put         @ Call gpio_put to drive the LED off
    b svc_done @ Return to the main SVC handler when finished


    @ Jump table for SVC function handlers
    .align 2
svc_jmptbl:
    .word svc_num0 @ Table entry 0 points to SVC handler 0
    .word svc_num1 @ Table entry 1 points to SVC handler 1
    .word 0 @ Marks the end of the jump table

    @ Align the data section
    .data
    .align 4