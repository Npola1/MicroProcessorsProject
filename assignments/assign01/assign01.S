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
        bl    printf                                            @ Output greeting to UART/USB

        BL      install_alarm_isr                               @ Map Timer handler
        BL      install_gpio_isr                                @ Map Button handler
        BL      init_leds                                       @ Configure GPIO 25
        BL      init_btns                                       @ Configure GPIO 20-22
main_loop:
        BL      set_alarm                                       @ Schedule next blink event
        wfi                                                     @ Sleep CPU until hardware interrupt
        B       main_loop                                       @ Resume cycle after IRQ

.thumb_func
install_alarm_isr:
        @ Locate the Vector Table in RAM using the VTOR register
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)            
        LDR     R1, [R2]                                        
        LDR     R2, =ALRM_ISR_OFFSET                            
        ADD     R2, R1                                          @ Calculate specific ISR slot

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
set_alarm:
       @ Wipe the Timer 0 interrupt flag to allow new triggers
       LDR     R2, =(TIMER_BASE + TIMER_INTR_OFFSET)             
       LDR     R1, =1
       STR     R1, [R2]

       @ Enable the Alarm 0 hardware signal
       LDR     R2, =(TIMER_BASE + TIMER_INTE_OFFSET)             
       LDR     R1, =1
       STR     R1, [R2]

       @ Capture current system time (Lower 32-bits)
       LDR     R2, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)          
       LDR     R3, [R2]

       @ Add the user-defined delta (ltimer) to current time
       LDR     R2, =ltimer                                       
       LDR     R1, [R2]
       ADDS    R3, R1

       @ Load the calculated timestamp into the hardware comparator
       LDR     R2, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR     R3, [R2]
       BX      LR


.thumb_func
alrm_isr:
       PUSH   {LR}                                              
       
       @ Visual ping: ensure RGB indicates processing (clearing state)
       MOVS   R0, #0                                            
       BL     asm_set_led_color                                 

       @ Standard interrupt acknowledgment (clear bit 0)
       LDR    R2, =(TIMER_BASE + TIMER_INTR_OFFSET) 
       MOVS   R1, #1                                            
       STR    R1, [R2]

       @ Notify console of the tick event
       LDR    R0, =alarm                                        
       bl     printf                                            

       @ Verify if blinking is currently authorized by the software state
       LDR    R4, =lstate                                       
       LDR    R4, [R4]                                          
       CMP    R4, #DFLT_STATE_STRT                              
       BNE    alarm_done                                        @ Abort if state is "Stop"

       @ Toggle Logic: Sample current GPIO state and invert it
       MOVS   R0, #GPIO_LED_PIN                                 
       BL     asm_gpio_get                                      
       CMP    R0, #LED_VAL_OFF                                  
       BEQ    led_set_on                                        

led_set_off:
       MOVS   R1, #LED_VAL_OFF                                  
       B      led_set_state                                     

led_set_on:
       MOVS   R1, #LED_VAL_ON                                   

led_set_state:
       MOVS   R0, #GPIO_LED_PIN                                 
       BL     asm_gpio_put                                      @ Apply the new logic level
       BL     set_alarm                                         @ Re-arm for the next toggle

alarm_done:
       POP    {PC}                                              

.thumb_func
gpio_isr:
       PUSH   {LR}                                              

       @ Probe which GPIO pin generated the event via INTS register
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                          
                                                                     
       @ Section: Logic for GP20 (Frequency Reduction)
       LDR    R3, =GPIO_BTN_DN_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    not_dn                                            

       @ Check if we are resetting a paused state or modifying an active one
       LDR    R4, =lstate                                       
       LDR    R5, [R4]                                          
       CMP    R5, #1                                            
       BEQ    not_paused                                        

       @ Reset Logic: Restore default 1s timing
       LDR    R4, =ltimer                                       
       LDR    R5, =DFLT_ALARM_TIME                              

       @ User Feedback: Flash Red and print reset info
       MOVS   R0, #1                                            
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       STR    R5, [R4]                                          
       LDR    R0, =led_reset                                    
       BL     printf                                            
       B      end                                               

not_paused:                 
       @ Speed Mod: Double the microsecond delay (Slower)
       LDR    R1, =ltimer                                       
       LDR    R3, [R1]                                          
       LSLS   R3, #1                                            
       STR    R3, [R1]                                          

       MOVS   R0, #1                                            @ Red Feedback
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       LDR    R0, =button_dn                                    
       bl     printf                                            
       b      end                                               

not_dn:
       @ Section: Logic for GP21 (Toggle Start/Stop)
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                          
       LDR    R3, =GPIO_BTN_EN_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    not_en                                            

       LDR    R2, =lstate                                       
       LDR    R3, [R2]                                          
       CMP    R3, #1                                            
       BNE    start_timer                                       
        
       @ Pause Execution
       MOVS   R0, #3                                            @ Blue Feedback
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       LDR    R1, =DFLT_STATE_STOP                              
       LDR    R2, =lstate                                       
       STR    R1, [R2]                                          

       @ Kill any pending hardware alarms
       LDR    R2, =(TIMER_BASE + TIMER_ARMED_OFFSET)            
       MOVS   R1, #1                                            
       STR    R1, [R2]                                          
       LDR    R2, =(TIMER_BASE + TIMER_INTR_OFFSET)             
       MOVS   R1, #1                                            
       STR    R1, [R2]                                          

       LDR    R0, =led_pause                                    
       BL     printf                                            
       B      end                                               

start_timer:  
       MOVS   R0, #3                                            @ Blue Feedback
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       LDR    R1, =DFLT_STATE_STRT                              
       LDR    R2, =lstate                                       
       STR    R1, [R2]                                          
       BL     set_alarm                                         
       LDR    R0, =led_restart                                  
       BL     printf                                            
       B      end                                               
        
not_en:
       @ Section: Logic for GP22 (Frequency Increase)
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                          
       LDR    R3, =GPIO_BTN_UP_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    end                                               

       LDR    R4, =lstate                                       
       LDR    R5, [R4]                                          
       CMP    R5, #1                                            
       BEQ    not_paused_up                                     

       @ Handle Reset from Pause
       MOVS   R0, #2                                            @ Green Feedback
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       LDR    R5, =DFLT_ALARM_TIME                              
       LDR    R4, =ltimer                                       
       STR    R5, [R4]                                          
       LDR    R0, =led_reset                                    
       BL     printf                                            
       B      end                                               

not_paused_up:                                                                                                  
       @ Speed Mod: Shift right (Halve delay / Increase Speed)
       LDR    R1, =ltimer                                       
       LDR    R3, [R1]                                          
       ASRS   R3, #1                                            
       STR    R3, [R1]                                          

       MOVS   R0, #2                                            @ Green Feedback
       BL     asm_set_led_color                                 
       LDR    R2, = COLOUR_PTRN_TIME                            
       LDR    R1, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)         
       LDR    R0, [R1]                                          
       ADDS   R0, R0, R2                                        
       LDR    R1, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR    R0, [R1]                                          

       LDR    R0, =button_up                                    
       bl     printf                                            
       b      end                                               

end:                                                                                                            
       @ Hardware requirement: Clear the raw GPIO edge flags in the BANK0 status registers
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)      
       LDR    R1, [R2]                                          
       STR    R1, [R2]                                          
       POP    {PC}                                              


.align 4
msg:          .asciz "Hello Assignment #01!\n"
alarm:        .asciz "Timer Alarm Triggered \n"
button_dn:    .asciz "GP20 is pressed & LED flashing rate halved \n"
button_up:    .asciz "GP22 is pressed & LED flashing rate doubled \n"
led_reset:    .asciz "LED Flasing Rate reset \n"
led_pause:    .asciz "LED paused\n"
led_restart:  .asciz "LED restarted\n"

.data                                                           
lstate: .word DFLT_STATE_STRT
ltimer: .word DFLT_ALARM_TIME