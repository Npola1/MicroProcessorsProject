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
.equ    COLOUR_PTRN_TIME, 5000                              
.equ    DFLT_STATE_STRT, 1                                     
.equ    DFLT_STATE_STOP, 0                                 
.equ    DFLT_ALARM_TIME, 1000000                              

/* --- Bitmasks for GPIO Events (Falling Edges) --- */
.equ    GPIO_BTN_DN_MSK, 0x00040000                           
.equ    GPIO_BTN_EN_MSK, 0x00400000                         
.equ    GPIO_BTN_UP_MSK, 0x04000000                       

/* --- Physical Pin Assignments --- */
.equ    GPIO_BTN_DN,    20                                      
.equ    GPIO_BTN_EN,    21                                      
.equ    GPIO_BTN_UP,    22                                      
.equ    GPIO_LED_PIN,   25                              
.equ    GPIO_DIR_IN,    0                                       
.equ    GPIO_DIR_OUT,   1                                       

.equ    LED_VAL_ON,     1                                       
.equ    LED_VAL_OFF,    0                                       

/* --- NVIC Vector Table Offsets --- */
.equ    GPIO_ISR_OFFSET,    0x74                             
.equ    ALRM_ISR_OFFSET,    0x40                       

.text
.thumb_func
main_asm:
        LDR   R0, =msg
        bl    printf                                 

        BL      install_alarm_isr                          
        BL      install_gpio_isr                      
        BL      init_leds                              
        BL      init_btns                           
main_loop:
        BL      set_alarm                           
        wfi          
        B       main_loop

.thumb_func
install_alarm_isr:
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)            
        LDR     R1, [R2]                                        
        LDR     R2, =ALRM_ISR_OFFSET                            
        ADD     R2, R1

        LDR     R0, =alrm_isr                                   
        STR     R0, [R2]                                        

        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)       
        LDR     R0, =1                                          
        STR     R0, [R2]                                        

        LDR     R2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)       
        LDR     R0, =1                                          
        STR     R0, [R2]                                        

        BX      LR                                              

install_gpio_isr:
        LDR     R2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)            
        LDR     R1, [R2]                                        
        LDR     R2, =GPIO_ISR_OFFSET                            
        ADD     R2, R1                                          

        LDR     R0, =gpio_isr                                   
        STR     R0, [R2]                                        
        
        LDR     R0, =1                                          
        LSLS    R0, #13                                         
        
        LDR     R1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)       
        STR     R0, [R1]                                        
        LDR     R1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)       
        STR     R0, [R1]                                        
        BX      LR                                              

init_leds:                                                      
       PUSH   {LR}                                              
       MOVS   R0, #GPIO_LED_PIN                                 
       BL     asm_gpio_init
       MOVS   R0, #GPIO_LED_PIN                                 
       MOVS   R1, #GPIO_DIR_OUT                                 
       BL     asm_gpio_set_dir
       MOVS   R0, #GPIO_LED_PIN                                 
       MOVS   R1, #LED_VAL_OFF                                  
       BL     asm_gpio_put
       POP    {PC}                                              

init_btns:
       PUSH   {LR}                                              
       MOVS   R0, #GPIO_BTN_DN                                 
       BL     asm_gpio_set_irq
       MOVS   R0, #GPIO_BTN_DN                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir
       
       MOVS   R0, #GPIO_BTN_EN                                 
       BL     asm_gpio_set_irq
       MOVS   R0, #GPIO_BTN_EN                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir                                  
       
       MOVS   R0, #GPIO_BTN_UP                                 
       BL     asm_gpio_set_irq
       MOVS   R0, #GPIO_BTN_UP                                 
       MOVS   R1, #GPIO_DIR_IN                                  
       BL     asm_gpio_set_dir                                  
       POP    {PC}                                              


.thumb_func
set_alarm:
       LDR     R2, =(TIMER_BASE + TIMER_INTR_OFFSET)             
       LDR     R1, =1
       STR     R1, [R2]
       LDR     R2, =(TIMER_BASE + TIMER_INTE_OFFSET)             
       LDR     R1, =1
       STR     R1, [R2]
       LDR     R2, =(TIMER_BASE + TIMER_TIMERAWL_OFFSET)          
       LDR     R3, [R2]
       LDR     R2, =ltimer                                       
       LDR     R1, [R2]
       ADDS    R3, R1
       LDR     R2, =(TIMER_BASE + TIMER_ALARM0_OFFSET)           
       STR     R3, [R2]
       BX      LR


.thumb_func
alrm_isr:
       PUSH   {LR}                                              
       
       MOVS   R0, #0                                            
       BL     asm_set_led_color                                 
       LDR    R2, =(TIMER_BASE + TIMER_INTR_OFFSET) 
       MOVS   R1, #1                                            
       STR    R1, [R2]
       LDR    R0, =alarm                                        
       bl     printf                                            
       LDR    R4, =lstate                                       
       LDR    R4, [R4]                                          
       CMP    R4, #DFLT_STATE_STRT                              
       BNE    alarm_done
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
       BL     asm_gpio_put
       BL     set_alarm

alarm_done:
       POP    {PC}                                              

.thumb_func
gpio_isr:
       PUSH   {LR}                                              

       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                                                                   
       LDR    R3, =GPIO_BTN_DN_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    notDone                                         
       LDR    R4, =lstate                                       
       LDR    R5, [R4]                                          
       CMP    R5, #1                                            
       BEQ    unpaused                                        

       LDR    R4, =ltimer                                       
       LDR    R5, =DFLT_ALARM_TIME                              

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

unpaused:                 
       LDR    R1, =ltimer                                       
       LDR    R3, [R1]                                          
       LSLS   R3, #1                                            
       STR    R3, [R1]                                          

       MOVS   R0, #1
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

notDone:
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                          
       LDR    R3, =GPIO_BTN_EN_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    unEnd                                 

       LDR    R2, =lstate                                       
       LDR    R3, [R2]                                          
       CMP    R3, #1                                            
       BNE    start_timer                                       
        
       MOVS   R0, #3
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
       MOVS   R0, #3
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
        
unEnd:
       LDR    R2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) 
       LDR    R1, [R2]                                          
       LDR    R3, =GPIO_BTN_UP_MSK                              
       ANDS   R1, R3                                            
       CMP    R1, R3                                            
       BNE    end                                               

       LDR    R4, =lstate                                       
       LDR    R5, [R4]                                          
       CMP    R5, #1                                            
       BEQ    upUnpaused                                

       MOVS   R0, #2
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

upUnpaused:                                                                                                  
       LDR    R1, =ltimer                                       
       LDR    R3, [R1]                                          
       ASRS   R3, #1                                            
       STR    R3, [R1]                                          

       MOVS   R0, #2
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