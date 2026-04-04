#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>

#include "hardware/gpio.h"
#include "pico/stdlib.h"
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "hardware/timer.h"
#include "ws2812.pio.h"

#define IS_RGBW true
#define NUM_PIXELS 1
#define WS2812_PIN 28

#define BUTTON_PIN 21
#define BUZZER_PIN 20

#define LETTER_GAP_US      1000000u
#define SEQUENCE_GAP_US    2000000u

#define MORSE_BUFFER_SIZE     8
#define SEQUENCE_BUFFER_SIZE 32

static PIO pio = pio0;
static int sm = 0;

/* ---------------- WS2812 ---------------- */

static inline void put_pixel(uint32_t pixel_grb) {
    pio_sm_put_blocking(pio0, 0, pixel_grb << 8u);
}

static inline uint32_t urgb_u32(uint8_t r, uint8_t g, uint8_t b) {
    return ((uint32_t)(r) << 8) |
           ((uint32_t)(g) << 16) |
           (uint32_t)(b);
}

void rgb_init(void) {
    uint offset = pio_add_program(pio, &ws2812_program);
    ws2812_program_init(pio, sm, offset, WS2812_PIN, 800000, IS_RGBW);
}

void set_rgb(uint8_t r, uint8_t g, uint8_t b) {
    uint32_t pixel = urgb_u32(r, g, b);
    put_pixel(pixel);
}

/* ---------------- BUZZER ---------------- */

void buzzer_init(void) {
    gpio_init(BUZZER_PIN);
    gpio_set_dir(BUZZER_PIN, GPIO_OUT);
    gpio_put(BUZZER_PIN, 0);
}

static void buzzer_tone(uint32_t period_us, uint32_t duration_us) {
    if (period_us == 0 || duration_us == 0) {
        return;
    }

    uint32_t half_period = period_us / 2;
    if (half_period == 0) {
        half_period = 1;
    }

    uint32_t cycles = duration_us / period_us;
    if (cycles == 0) {
        cycles = 1;
    }

    for (uint32_t i = 0; i < cycles; i++) {
        gpio_put(BUZZER_PIN, 1);
        sleep_us(half_period);
        gpio_put(BUZZER_PIN, 0);
        sleep_us(half_period);
    }

    gpio_put(BUZZER_PIN, 0);
}

void play_dot_sound(void) {
    /* higher pitch, shorter */
    buzzer_tone(1000, 120000);
}

void play_dash_sound(void) {
    /* lower pitch, longer */
    buzzer_tone(1600, 300000);
}

void play_levelup_sound(void) {
    /* simple ascending 3 note pattern */
    buzzer_tone(1800, 120000);
    sleep_ms(40);
    buzzer_tone(1400, 120000);
    sleep_ms(40);
    buzzer_tone(1000, 180000);
}

/* ---------------- ASM INTERFACE ---------------- */

void main_asm(void);
void entered_dot(void);
void entered_dash(void);
void player_win(void);
void player_lose(void);
void led_off(void);
void answer_correct(void);
void answer_wrong(void);
void play_levelup_sound(void);

void asm_gpio_callback_handler(uint gpio, uint32_t events);
void asm_clear_morse_buffer(void);

/* Shared state owned by ASM input logic */
extern volatile uint32_t press_start_time_asm;
extern volatile uint32_t last_irq_time_asm;
extern volatile uint32_t last_input_time_asm;
extern volatile uint32_t last_press_timestamp_asm;
extern volatile uint32_t last_release_timestamp_asm;
extern volatile uint32_t press_duration_asm;
extern volatile uint32_t inter_press_interval_asm;
extern volatile uint32_t waiting_for_release_asm;
extern volatile uint32_t morse_index_asm;
extern volatile char morse_buffer_asm[MORSE_BUFFER_SIZE];

/* ---------------- GPIO WRAPPERS ---------------- */

void asm_gpio_init(uint pin) {
    gpio_init(pin);
}

void asm_gpio_set_dir(uint pin, bool out) {
    gpio_set_dir(pin, out);
}

bool asm_gpio_get(uint pin) {
    return gpio_get(pin);
}

void asm_gpio_put(uint pin, bool value) {
    gpio_put(pin, value);
}

uint32_t asm_time_us_32(void) {
    return time_us_32();
}

/* Thin C trampoline: actual handler logic is in ASM */
void gpio_callback(uint gpio, uint32_t events) {
    asm_gpio_callback_handler(gpio, events);
}

void asm_gpio_set_irq(uint pin) {
    gpio_pull_up(pin);

    gpio_set_irq_enabled_with_callback(
        pin,
        GPIO_IRQ_EDGE_FALL | GPIO_IRQ_EDGE_RISE,
        true,
        &gpio_callback
    );
}

/* ---------------- MORSE DECODING IN C ---------------- */

typedef struct {
    const char *pattern;
    char symbol;
} MorseEntry;

static const MorseEntry morse_table[] = {
    {".-",    'A'}, {"-...",  'B'}, {"-.-.",  'C'}, {"-..",   'D'},
    {".",     'E'}, {"..-.",  'F'}, {"--.",   'G'}, {"....",  'H'},
    {"..",    'I'}, {".---",  'J'}, {"-.-",   'K'}, {".-..",  'L'},
    {"--",    'M'}, {"-.",    'N'}, {"---",   'O'}, {".--.",  'P'},
    {"--.-",  'Q'}, {".-.",   'R'}, {"...",   'S'}, {"-",     'T'},
    {"..-",   'U'}, {"...-",  'V'}, {".--",   'W'}, {"-..-",  'X'},
    {"-.--",  'Y'}, {"--..",  'Z'},

    {".----", '1'}, {"..---", '2'}, {"...--", '3'}, {"....-", '4'},
    {".....", '5'}, {"-....", '6'}, {"--...", '7'}, {"---..", '8'},
    {"----.", '9'}, {"-----", '0'}
};

static char decode_morse(const char *pattern) {
    size_t count = sizeof(morse_table) / sizeof(morse_table[0]);
    for (size_t i = 0; i < count; i++) {
        if (strcmp(pattern, morse_table[i].pattern) == 0) {
            return morse_table[i].symbol;
        }
    }
    return '?';
}

/* ---------------- LEVEL-BASED CHALLENGE SYSTEM ---------------- */

#define MAX_WORD_LENGTH 8
#define QUESTIONS_PER_LEVEL 5

typedef struct {
    const char *text;
} Challenge;

/* ---------- LEVEL DEFINITIONS ---------- */
/*Level 1 - Challenege set hints allowed*/
static const Challenge level1_set[QUESTIONS_PER_LEVEL] = {
    {"T"}, {"P"}, {"2"}, {"I"}, {"4"}
};

/*Level 2 - Challeneg set no hints allowed*/
static const Challenge level2_set[QUESTIONS_PER_LEVEL] = {
    {"17"}, {"IN"}, {"18"}, {"IS"}, {"OR"}
};

/*Level 3 - Challenge set hints allowed*/
static const Challenge level3_set[QUESTIONS_PER_LEVEL] = {
    {"FOR"}, {"DOOR"}, {"67"}, {"BALL"}, {"56"}
};

/*Level 4 -  Challenge set no hints allowed*/
static const Challenge level4_set[QUESTIONS_PER_LEVEL] = {
    {"212"}, {"POOR"}, {"POUR"}, {"KNIGHT"}, {"111"}
};

/* ---------- RUNTIME STATE ---------- */

static int questions_asked = 0;

static char current_expected_text[MAX_WORD_LENGTH];
static char current_morse_hint[32];

/* ---------- MORSE ENCODING(TEXT -> MORSE) --------*/
static const char* encode_morse_char(char c){
    size_t count = sizeof(morse_table)/sizeof(morse_table[0]);

    for(size_t i = 0; i< count; i++){
        if (morse_table[i].symbol == c) {
            return morse_table[i].pattern;
        }
    }
    return "?";
}

static void encode_text_to_morse(const char *text, char *out){
    out[0] = '\0';

    for(size_t i =0; i<strlen(text); i++){
        const char *m =encode_morse_char(text[i]);
        strcat(out, m);

        if (i != strlen(text) - 1) {
            strcat(out, " ");
        }
    }
}

/* ---------------- HIGH-LEVEL PARSER STATE ---------------- */

static char decoded_sequence[SEQUENCE_BUFFER_SIZE];
static int decoded_index = 0;

static bool letter_gap_handled = false;
static bool sequence_complete_handled = true;
static uint32_t last_seen_input_time = 0;

/* ---------------- GAME STATE (WEEK 2) ---------------- */

typedef enum {
    LEVEL_1 = 1,
    LEVEL_2,
    LEVEL_3,
    LEVEL_4
} GameLevel;

static bool game_started = false;
static GameLevel current_level = LEVEL_1;
static int consecutive_correct = 0;
static int player_lives = 3;

static void update_lives_led(void) {
    if (!game_started) {
        set_rgb(0, 0, 255);
        return;
    }

    switch (player_lives) {
        case 3:
            set_rgb(0, 255, 0);      /* green */
            break;
        case 2:
            set_rgb(255, 255, 0);    /* yellow */
            break;
        case 1:
            set_rgb(255, 80, 0);     /* orange/red */
            break;
        default:
            set_rgb(255, 0, 0);      /* red */
            break;
    }
}

static void clear_decoded_sequence(void) {
    decoded_index = 0;
    decoded_sequence[0] = '\0';
}

static void on_new_input_detected(void) {
    if (sequence_complete_handled) {
        clear_decoded_sequence();
    }
    letter_gap_handled = false;
    sequence_complete_handled = false;
}

static void finalize_current_letter(void) {
    uint32_t len = morse_index_asm;
    if (len == 0) {
        return;
    }

    char local_morse[MORSE_BUFFER_SIZE];
    if (len >= MORSE_BUFFER_SIZE) {
        len = MORSE_BUFFER_SIZE - 1;
    }

    for (uint32_t i = 0; i < len; i++) {
        local_morse[i] = (char)morse_buffer_asm[i];
    }
    local_morse[len] = '\0';

    char decoded = decode_morse(local_morse);

    if (decoded == '?') {
        printf("Invalid Morse: %s\n", local_morse);
        return;
    }

    if (decoded_index < SEQUENCE_BUFFER_SIZE - 1) {
        decoded_sequence[decoded_index++] = decoded;
        decoded_sequence[decoded_index] = '\0';
    }

    printf("Letter complete: %s -> %c\n", local_morse, decoded);

    asm_clear_morse_buffer();
    letter_gap_handled = true;
}

static void print_level_banner(void) {
    printf("\n========== LEVEL %d ==========\n", current_level);

    switch (current_level) {
        case LEVEL_1:
            printf("Mode: Character WITH Morse hint\n");
            break;
        case LEVEL_2:
            printf("Mode: Character WITHOUT Morse hint\n");
            break;
        case LEVEL_3:
            printf("Mode: Word WITH Morse hint\n");
            break;
        case LEVEL_4:
            printf("Mode: Word WITHOUT Morse hint\n");
            break;
        default:
            printf("Mode: Unknown\n");
            break;
    }

    printf("Need 5 consecutive correct answers to advance.\n");
    printf("=============================\n\n");
}

static void print_lives_status(void) {
    printf("Lives: %d/3\n", player_lives);
}

static void lose_life(void) {
    if (player_lives > 0) {
        player_lives--;
    }

    printf("Incorrect! Lost 1 life.\n");
    print_lives_status();

    /* temporary feedback for life loss */
    set_rgb(255, 0, 0);
    sleep_ms(300);
    update_lives_led();

    if (player_lives <= 0) {
        printf("\n*** GAME OVER: No lives remaining ***\n");
        player_lose();
        game_started = false;
    }
}

static void gain_life(void) {
    if (player_lives < 3) {
        player_lives++;
        printf("Correct! Gained 1 life.\n");
    } else {
        printf("Correct! Lives already full.\n");
    }

    print_lives_status();
    update_lives_led();
}

/* forward declaration for function used later */
static void generate_next_challenge(void);

static void advance_level(void) {
    if (current_level < LEVEL_4) {
        current_level++;
        consecutive_correct = 0;
        questions_asked = 0;

        printf("\n*** LEVEL UP! Now entering Level %d ***\n", current_level);
        play_levelup_sound();
        print_level_banner();
    } else {
        printf("\n*** Congratulations! You completed all levels! ***\n");
        player_win();
        game_started = false;
    }
}

static const Challenge* get_current_level_set(void){
    switch(current_level){
        case LEVEL_1: return level1_set;
        case LEVEL_2: return level2_set;
        case LEVEL_3: return level3_set;
        case LEVEL_4: return level4_set;
        default: return level1_set;
    }
}

static bool level_has_hint(void){
    return(current_level == LEVEL_1 || current_level == LEVEL_3);
}

static void generate_next_challenge(void){
    const Challenge *set = get_current_level_set();

    if (questions_asked >= QUESTIONS_PER_LEVEL) {
        printf("All questions completed for this level.\n");
        return;
    }

    const char *selected = set[questions_asked].text;

    strncpy(current_expected_text, selected, MAX_WORD_LENGTH);
    current_expected_text[MAX_WORD_LENGTH - 1] = '\0';

    if (level_has_hint()) {
        encode_text_to_morse(current_expected_text, current_morse_hint);
        printf("Target: %s\n", current_expected_text);
        printf("Morse Hint: %s\n", current_morse_hint);
    } else {
        printf("Target: %s\n", current_expected_text);
    }

    questions_asked++;
}

static void handle_answer_result(bool is_correct) {
    if (is_correct) {
        answer_correct();

        consecutive_correct++;
        gain_life();
        printf("Streak: %d/5\n", consecutive_correct);

        if (consecutive_correct >= 5) {
            advance_level();
            generate_next_challenge();
        } else {
            generate_next_challenge();
        }
    } else {
        answer_wrong();

        consecutive_correct = 0;
        printf("Incorrect. Streak reset.\n");

        /* use lives system */
        lose_life();

        /* still generate next challenge */
        generate_next_challenge();
    }
}

static void string_normalization(char *str){
    int wr = 0;
    for(int re = 0; str[re] != '\0'; re++){
        char c = str[re];

        if(c >= 'a' && c<= 'z'){
            c = c - 'a' + 'A';
        }

        /* keep only A-Z and 0-9 */
        if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')){
            str[wr] = c;
            wr++;
        }
    }
    str[wr] = '\0';
}

static bool evaluate_current_sequence(void) {
    char input_copy[SEQUENCE_BUFFER_SIZE];
    char expected_copy[MAX_WORD_LENGTH];

    /* copy strings */
    strncpy(input_copy, decoded_sequence, SEQUENCE_BUFFER_SIZE);
    strncpy(expected_copy, current_expected_text, MAX_WORD_LENGTH);

    input_copy[SEQUENCE_BUFFER_SIZE - 1] = '\0';
    expected_copy[MAX_WORD_LENGTH - 1] = '\0';

    /* normalize both */
    string_normalization(input_copy);
    string_normalization(expected_copy);

    printf("DEBUG -> Input: \"%s\" | Expected: \"%s\"\n", input_copy, expected_copy);

    return strcmp(input_copy, expected_copy) == 0;
}

static void finalize_sequence(void) {
    if (sequence_complete_handled) {
        return;
    }

    printf("Sequence complete: \"%s\"\n", decoded_sequence);

    if (game_started) {
        bool is_correct = evaluate_current_sequence();
        handle_answer_result(is_correct);
    } else {
        printf("Game not started.\n");
    }

    printf("----------------------------------------\n");

    sequence_complete_handled = true;
    update_lives_led();
}

/* ---------------- MAIN ---------------- */

int main(void) {
    stdio_init_all();
    sleep_ms(2000);

    printf("\n========================================\n");
    printf(" CSU23021 - Assignment 02 - Week 1\n");
    printf(" Morse Input Parser Test\n");
    printf(" GP21 active\n");
    printf(" Short press  -> DOT\n");
    printf(" Long press   -> DASH\n");
    printf(" 1 second gap -> end current letter\n");
    printf(" 2 second gap -> end current sequence\n");
    printf("========================================\n\n");

    rgb_init();
    buzzer_init();
    set_rgb(0, 0, 255);   /* idle blue */

    asm_clear_morse_buffer();
    clear_decoded_sequence();

    game_started = true;
    current_level = LEVEL_1;
    consecutive_correct = 0;
    player_lives = 3;

    printf("\n[Game Started]\n");
    print_level_banner();

    print_lives_status();
    update_lives_led();
    generate_next_challenge();

    main_asm();   /* init GPIO/LED/IRQ in ASM, then return */

    while (true) {
        uint32_t now = time_us_32();

        if (last_input_time_asm != 0 && last_input_time_asm != last_seen_input_time) {
            last_seen_input_time = last_input_time_asm;
            on_new_input_detected();
        }

        if (last_input_time_asm != 0) {
            uint32_t idle_time = now - last_input_time_asm;

            if (!letter_gap_handled &&
                morse_index_asm > 0 &&
                idle_time >= LETTER_GAP_US) {
                finalize_current_letter();
            }

            if (!sequence_complete_handled &&
                decoded_index > 0 &&
                idle_time >= SEQUENCE_GAP_US) {
                finalize_sequence();
            }
        }

        sleep_ms(10);
    }

    return 0;
}