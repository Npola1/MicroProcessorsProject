/**
 * @file    lab11.S
 * @brief   CSU23021 Lab #11 – Assembly section
 *
 * @details Assembly side responsibilities:
 *            - Initialise the RP2040 ADC for the built-in temperature sensor
 *            - Install Timer Alarm 0 ISR
 *            - Read the ADC once per second
 *            - Store the raw value in shared memory
 *            - Call the C function to convert, print, and set LED colour
 */

#include "hardware/regs/addressmap.h"
#include "hardware/regs/adc.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified
.cpu    cortex-m0plus
.thumb
.global lab11_core
.align  4

/* ------------------------------------------------------------------------- */
/* Timer constants                                                           */
/* ------------------------------------------------------------------------- */

.equ    TIMER0_VECTOR_OFFSET,     0x40
.equ    SAMPLE_PERIOD_US,         1000000

/* ------------------------------------------------------------------------- */
/* ADC constants                                                             */
/* ------------------------------------------------------------------------- */

.equ    ADC_TEMP_CFG,             0x4003
.equ    ADC_TEMP_START,           0x4007
.equ    ADC_READY_BIT,            0x100
.equ    ADC_12BIT_MASK,           0xFFF

/* ------------------------------------------------------------------------- */
/* lab11_core                                                                */
/* ------------------------------------------------------------------------- */

lab11_core:
        BL      adc_temperature_init
        BL      timer0_isr_install
        BL      schedule_next_sample

sleep_forever:
        WFI
        B       sleep_forever

/* ------------------------------------------------------------------------- */
/* adc_temperature_init                                                      */
/* ------------------------------------------------------------------------- */

.thumb_func
adc_temperature_init:
        LDR     R2, =(ADC_BASE + ADC_CS_OFFSET)
        LDR     R1, =ADC_TEMP_CFG
        STR     R1, [R2]
        BX      LR

/* ------------------------------------------------------------------------- */
/* timer0_isr_install                                                        */
/* ------------------------------------------------------------------------- */

.thumb_func
timer0_isr_install:
        @ Load vector table base
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)
        LDR     R1, [R2]

        @ Address of Timer Alarm 0 vector slot
        LDR     R2, =TIMER0_VECTOR_OFFSET
        ADDS    R2, R2, R1

        @ Install ISR address
        LDR     R0, =timer0_sample_handler
        STR     R0, [R2]

        @ Clear pending NVIC interrupt for Timer 0
        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
        MOVS    R0, #1
        STR     R0, [R2]

        @ Enable NVIC interrupt for Timer 0
        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
        MOVS    R0, #1
        STR     R0, [R2]

        BX      LR

/* ------------------------------------------------------------------------- */
/* schedule_next_sample                                                      */
/* ------------------------------------------------------------------------- */

.thumb_func
schedule_next_sample:
        @ Clear any old timer interrupt flag
        LDR     R2, =(TIMER_BASE + TIMER_INTR_OFFSET)
        MOVS    R1, #1
        STR     R1, [R2]

        @ Enable Alarm 0 interrupt source
        LDR     R2, =(TIMER_BASE + TIMER_INTE_OFFSET)
        MOVS    R1, #1
        STR     R1, [R2]

        @ target = TIMERAWL + SAMPLE_PERIOD_US
        LDR     R2, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)
        LDR     R3, [R2]
        LDR     R1, =SAMPLE_PERIOD_US
        ADDS    R3, R3, R1

        @ Write target time to ALARM0
        LDR     R2, =(TIMER_BASE + TIMER_ALARM0_OFFSET)
        STR     R3, [R2]

        BX      LR

/* ------------------------------------------------------------------------- */
/* timer0_sample_handler                                                     */
/* ------------------------------------------------------------------------- */

.thumb_func
timer0_sample_handler:
        PUSH    {R4, R5, R6, R7, LR}

        @ Acknowledge Timer Alarm 0 interrupt
        LDR     R2, =(TIMER_BASE + TIMER_INTR_OFFSET)
        MOVS    R1, #1
        STR     R1, [R2]

        @ Start one ADC conversion
        LDR     R4, =(ADC_BASE + ADC_CS_OFFSET)
        LDR     R1, =ADC_TEMP_START
        STR     R1, [R4]

        @ Wait until READY goes low
        LDR     R2, =ADC_READY_BIT
wait_ready_clear:
        LDR     R1, [R4]
        ANDS    R1, R2
        CMP     R1, R2
        BEQ     wait_ready_clear

        @ Wait until READY goes high
wait_ready_set:
        LDR     R1, [R4]
        ANDS    R1, R2
        CMP     R1, R2
        BNE     wait_ready_set

        @ Read 12-bit ADC result
        LDR     R2, =(ADC_BASE + ADC_RESULT_OFFSET)
        LDR     R0, [R2]
        LDR     R3, =ADC_12BIT_MASK
        ANDS    R0, R3

        @ Store raw sample in shared variable
        LDR     R5, =latest_temp_adc_raw
        STR     R0, [R5]

        @ Call C function with raw value in R0
        LDR     R0, [R5]
        BL      update_temperature_state

        @ Rearm timer for next sample
        BL      schedule_next_sample

        POP     {R4, R5, R6, R7, PC}

/* ------------------------------------------------------------------------- */
/* Shared data                                                               */
/* ------------------------------------------------------------------------- */

.data
.align 4

latest_temp_adc_raw:
        .word   0