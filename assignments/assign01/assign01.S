#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                                                 
.cpu    cortex-m0plus                                           
.thumb                                                          
.global main_asm                                                
.align 4                             

/* --- Configuration Constants --- */
.equ    COLOUR_PTRN_TIME, 5000                                  @ Window for visual feedback (5ms)
.equ    DFLT_STATE_STRT, 1                                      @ Logic high for active blinker
.equ    DFLT_STATE_STOP, 0                                      @ Logic low for idle blinker
.equ    DFLT_ALARM_TIME, 1000000                                @ 1-second interval in microseconds

/* --- Bitmasks for GPIO Events (Falling Edges) --- */
.equ    GPIO_BTN_DN_MSK, 0x00040000                             @ Mask for GP20 trigger
.equ    GPIO_BTN_EN_MSK, 0x00400000                             @ Mask for GP21 trigger
.equ    GPIO_BTN_UP_MSK, 0x04000000                             @ Mask for GP22 trigger

/* --- Physical Pin Assignments --- */
.equ    GPIO_BTN_DN,    20                                      
.equ    GPIO_BTN_EN,    21                                      
.equ    GPIO_BTN_UP,    22                                      
.equ    GPIO_LED_PIN,   25                                      @ Onboard LED
.equ    GPIO_DIR_IN,    0                                       
.equ    GPIO_DIR_OUT,   1                                       

.equ    LED_VAL_ON,     1                                       
.equ    LED_VAL_OFF,    0                                       

/* --- NVIC Vector Table Offsets --- */
.equ    GPIO_ISR_OFFSET,    0x74                                @ Entry for External GPIO IRQ
.equ    ALRM_ISR_OFFSET,    0x40                                @ Entry for Timer Alarm 0 IRQ

.text
.thumb_func
main_asm:
        LDR   R0, =msg
        BL    printf

        BL      install_alarm_isr
        BL      install_gpio_isr
        BL      init_leds
        BL      init_btns
main_loop:
        BL      set_alarm
        WFI
        B       main_loop


.thumb_func
install_alarm_isr:
        @ Locate the Vector Table in RAM using the VTOR register
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)
        LDR     R1, [R2]
        LDR     R2, =ALRM_ISR_OFFSET
        ADD     R2, R1

        @ Assign the local alarm label to the vector table
        LDR     R0, =alrm_isr
        STR     R0, [R2]

        @ Acknowledge and clear any existing Timer 0 pending status
        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
        LDR     R0, =1
        STR     R0, [R2]

        @ Globally enable Timer 0 interrupts in the NVIC
        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
        LDR     R0, =1
        STR     R0, [R2]

        BX      LR                                             

install_gpio_isr:
        @ Fetch the RAM-based vector table address
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)
        LDR     R1, [R2]
        LDR     R2, =GPIO_ISR_OFFSET
        ADD     R2, R1

        @ Link the GPIO handler to the system vector table
        LDR     R0, =gpio_isr
        STR     R0, [R2]

        @ Target Bit 13 (External GPIO IRQ)
        LDR     R0, =1
        LSLS    R0, #13

        @ Flush pending GPIO IRQs and activate the line in NVIC
        LDR     R1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
        STR     R0, [R1]
        LDR     R1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
        STR     R0, [R1]
        BX      LR



init_leds:                                                      
       PUSH   {LR}                                              
       MOVS   R0, #GPIO_LED_PIN                                 
       BL     asm_gpio_init                                     @ Reset pin to SIO function
       MOVS   R0, #GPIO_LED_PIN                                 
       MOVS   R1, #GPIO_DIR_OUT                                 
       BL     asm_gpio_set_dir                                  @ Define as output
       MOVS   R0, #GPIO_LED_PIN                                 
       MOVS   R1, #LED_VAL_OFF                                  
       BL     asm_gpio_put                                      @ Initial state: Dark
       POP    {PC}                                              

init_btns:
       PUSH   {LR}                                              
       MOVS   R0, #GPIO_BTN_DN                                 
       BL     asm_gpio_set_irq                                  @ Register falling edge for GP20
       MOVS   R0, #GPIO_BTN_DN                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir                                  @ Define as input
       
       MOVS   R0, #GPIO_BTN_EN                                 
       BL     asm_gpio_set_irq                                  @ Register falling edge for GP21
       MOVS   R0, #GPIO_BTN_EN                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir                                  
       
       MOVS   R0, #GPIO_BTN_UP                                 
       BL     asm_gpio_set_irq                                  @ Register falling edge for GP22
       MOVS   R0, #GPIO_BTN_UP                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir                                  
       POP    {PC}


.thumb_func
alrm_isr:
BX LR



.align 4
msg:    .asciz "Hello Assignment #01!\n"
alarm:        .asciz "Timer Alarm Triggered \n"

.data
.align 4
lstate: .word DFLT_STATE_STRT
ltimer: .word DFLT_ALARM_TIME