.syntax unified
.cpu cortex-m0plus
.thumb

.global main_asm
.global entered_dot
.global entered_dash
.global player_win
.global player_lose
.global led_off
.global asm_gpio_callback_handler
.global asm_clear_morse_buffer

.global press_start_time_asm
.global last_irq_time_asm
.global last_input_time_asm
.global last_press_timestamp_asm
.global last_release_timestamp_asm
.global press_duration_asm
.global inter_press_interval_asm
.global waiting_for_release_asm
.global morse_index_asm
.global morse_buffer_asm
.global answer_correct
.global answer_wrong

.align 4

.equ GPIO_BTN_EN,        21
.equ GPIO_LED_PIN,       25
.equ GPIO_DIR_IN,        0
.equ GPIO_DIR_OUT,       1
.equ LED_VAL_OFF,        0

.equ GPIO_IRQ_EDGE_FALL, 4
.equ GPIO_IRQ_EDGE_RISE, 8

.equ DOT_THRESHOLD_US,   250000
.equ DEBOUNCE_US,        20000
.equ MORSE_BUFFER_MAX,   7

.text
.thumb_func

.extern asm_gpio_set_irq
.extern asm_gpio_init
.extern asm_gpio_set_dir
.extern asm_gpio_put
.extern printf
.extern set_rgb
.extern asm_time_us_32
.extern play_dot_sound
.extern play_dash_sound
.extern play_levelup_sound

main_asm:
        PUSH {lr}
        BL init_leds
        BL init_btns
        POP {pc}

.thumb_func
init_leds:
        PUSH {lr}
        MOVS R0, #GPIO_LED_PIN
        BL asm_gpio_init

        MOVS R0, #GPIO_LED_PIN
        MOVS R1, #GPIO_DIR_OUT
        BL asm_gpio_set_dir

        MOVS R0, #GPIO_LED_PIN
        MOVS R1, #LED_VAL_OFF
        BL asm_gpio_put
        POP {pc}

.thumb_func
init_btns:
        PUSH {lr}

        MOVS R0, #GPIO_BTN_EN
        BL asm_gpio_init

        MOVS R0, #GPIO_BTN_EN
        MOVS R1, #GPIO_DIR_IN
        BL asm_gpio_set_dir

        MOVS R0, #GPIO_BTN_EN
        BL asm_gpio_set_irq

        POP {pc}

.thumb_func
asm_clear_morse_buffer:
        PUSH {lr}
        LDR R0, =morse_index_asm
        MOVS R1, #0
        STR R1, [R0]

        LDR R0, =morse_buffer_asm
        STRB R1, [R0]
        POP {pc}

.thumb_func
asm_append_symbol:
        PUSH {R4-R5, lr}

        LDR R1, =morse_index_asm
        LDR R2, [R1]
        CMP R2, #MORSE_BUFFER_MAX
        BHS asm_append_done

        LDR R3, =morse_buffer_asm
        ADDS R4, R3, R2
        STRB R0, [R4]

        ADDS R2, R2, #1
        STR R2, [R1]

        ADDS R3, R3, R2
        MOVS R5, #0
        STRB R5, [R3]

asm_append_done:
        POP {R4-R5, pc}

.thumb_func
asm_gpio_callback_handler:
        PUSH {R4-R7, lr}

        MOV  R6, R0              @ gpio
        MOV  R7, R1              @ events

        CMP  R6, #GPIO_BTN_EN
        BNE  handler_done

        BL   asm_time_us_32
        MOV  R4, R0              @ now

        @ debounce: if (now - last_irq_time) < DEBOUNCE_US return;
        LDR  R5, =last_irq_time_asm
        LDR  R0, [R5]
        SUBS R0, R4, R0
        LDR  R1, =DEBOUNCE_US
        CMP  R0, R1
        BLO  handler_done
        STR  R4, [R5]

        @ falling edge
        MOVS R0, #GPIO_IRQ_EDGE_FALL
        TST  R7, R0
        BEQ  check_rise

        LDR  R0, =press_start_time_asm
        STR  R4, [R0]

        LDR  R0, =last_press_timestamp_asm
        STR  R4, [R0]

        LDR  R0, =waiting_for_release_asm
        MOVS R1, #1
        STR  R1, [R0]

        @ interval between button presses = current press time - previous release time
        LDR  R0, =last_release_timestamp_asm
        LDR  R1, [R0]
        CMP  R1, #0
        BEQ  handler_done

        SUBS R2, R4, R1
        LDR  R0, =inter_press_interval_asm
        STR  R2, [R0]
        B    handler_done

check_rise:
        MOVS R0, #GPIO_IRQ_EDGE_RISE
        TST  R7, R0
        BEQ  handler_done

        LDR  R0, =waiting_for_release_asm
        LDR  R1, [R0]
        CMP  R1, #1
        BNE  handler_done

        MOVS R1, #0
        STR  R1, [R0]

        LDR  R0, =last_release_timestamp_asm
        STR  R4, [R0]

        @ duration = release_time - press_start_time
        LDR  R0, =press_start_time_asm
        LDR  R1, [R0]
        SUBS R5, R4, R1

        LDR  R0, =press_duration_asm
        STR  R5, [R0]

        LDR  R0, =last_input_time_asm
        STR  R4, [R0]

        LDR  R0, =DOT_THRESHOLD_US
        CMP  R5, R0
        BHS  handle_dash

handle_dot:
        BL   entered_dot
        MOVS R0, #'.'
        BL   asm_append_symbol
        B    handler_done

handle_dash:
        BL   entered_dash
        MOVS R0, #'-'
        BL   asm_append_symbol

handler_done:
        POP  {R4-R7, pc}

.thumb_func
entered_dot:
        PUSH {lr}
        LDR  R0, =msg_dot
        BL   printf

        MOVS R0, #0
        MOVS R1, #0
        MOVS R2, #255
        BL   set_rgb

        BL   play_dot_sound
        POP  {pc}

.thumb_func
entered_dash:
        PUSH {lr}
        LDR  R0, =msg_dash
        BL   printf

        MOVS R0, #255
        MOVS R1, #80
        MOVS R2, #0
        BL   set_rgb

        BL   play_dash_sound
        POP  {pc}

.thumb_func
answer_correct:
        PUSH {lr}
        LDR  R0, =msg_correct
        BL   printf

        @ RGB = Green
        MOVS R0, #0
        MOVS R1, #255
        MOVS R2, #0
        BL   set_rgb
        POP  {pc}

.thumb_func
answer_wrong:
        PUSH {lr}
        LDR  R0, =msg_wrong
        BL   printf

        @ RGB = Red
        MOVS R0, #255
        MOVS R1, #0
        MOVS R2, #0
        BL   set_rgb
        POP  {pc}

.thumb_func
player_win:
        PUSH {lr}
        LDR  R0, =msg_win
        BL   printf

        MOVS R0, #0
        MOVS R1, #255
        MOVS R2, #0
        BL   set_rgb
        POP  {pc}

.thumb_func
player_lose:
        PUSH {lr}
        LDR  R0, =msg_lose
        BL   printf

        MOVS R0, #255
        MOVS R1, #0
        MOVS R2, #0
        BL   set_rgb
        POP  {pc}

.thumb_func
led_off:
        PUSH {lr}
        MOVS R0, #0
        MOVS R1, #0
        MOVS R2, #0
        BL   set_rgb
        POP  {pc}

.data
.align 4
msg_dot:  .asciz "ASM feedback: DOT -> RGB Blue\n"
msg_dash: .asciz "ASM feedback: DASH -> RGB Orange\n"
msg_win:  .asciz "Game Over, You Won\n"
msg_lose: .asciz "Game Over, You Lost\n"
msg_correct: .asciz "Correct Answer -> RGB Green\n"
msg_wrong:   .asciz "Wrong Answer -> RGB Red\n"

.bss
.align 4
press_start_time_asm:       .space 4
last_irq_time_asm:          .space 4
last_input_time_asm:        .space 4
last_press_timestamp_asm:   .space 4
last_release_timestamp_asm: .space 4
press_duration_asm:         .space 4
inter_press_interval_asm:   .space 4
waiting_for_release_asm:    .space 4
morse_index_asm:            .space 4
morse_buffer_asm:           .space 8