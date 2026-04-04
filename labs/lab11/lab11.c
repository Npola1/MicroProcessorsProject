/**
 * @file    lab11.c
 * @brief   CSU23021 Lab #11 – Temperature reading and RGB colour output
 *
 * @details C side responsibilities:
 *            - Initialise USB stdio for printf output
 *            - Initialise the WS2812 LED using PIO
 *            - Convert a raw ADC sample to Celsius
 *            - Print the current reading
 *            - Set LED colour based on temperature band
 */

#include <stdio.h>
#include <stdint.h>
#include "pico/stdlib.h"
#include "hardware/pio.h"
#include "ws2812.pio.h"

/* ------------------------------------------------------------------------- */
/* WS2812 configuration                                                      */
/* ------------------------------------------------------------------------- */

#define WS2812_USES_RGBW      false
#define WS2812_DATA_GPIO      28
#define WS2812_PIO_BLOCK      pio0
#define WS2812_STATE_MACHINE  0

/* ------------------------------------------------------------------------- */
/* Temperature conversion constants                                          */
/* ------------------------------------------------------------------------- */

#define ADC_REFERENCE_VOLTAGE     3.3f
#define ADC_MAX_COUNT             4096.0f
#define SENSOR_VOLTAGE_AT_27C     0.706f
#define SENSOR_SLOPE_V_PER_C      0.001721f

/* Temperature bands used for LED colour selection */
#define TEMPERATURE_COLD_LIMIT    14.3f
#define TEMPERATURE_HOT_LIMIT     15.0f

/* ------------------------------------------------------------------------- */
/* Assembly entry point                                                      */
/* ------------------------------------------------------------------------- */
void lab11_core(void);

/* ------------------------------------------------------------------------- */
/* WS2812 helper functions                                                   */
/* ------------------------------------------------------------------------- */

/**
 * @brief Send one packed GRB value to the WS2812 LED.
 *
 * @param grb_word Packed 24-bit GRB colour word
 */
static inline void ws2812_send(uint32_t grb_word)
{
    pio_sm_put_blocking(WS2812_PIO_BLOCK, WS2812_STATE_MACHINE, grb_word << 8u);
}

/**
 * @brief Pack RGB bytes into the GRB order required by WS2812.
 *
 * @param red   Red intensity
 * @param green Green intensity
 * @param blue  Blue intensity
 * @return Packed GRB colour word
 */
static inline uint32_t pack_ws2812_colour(uint8_t red, uint8_t green, uint8_t blue)
{
    return ((uint32_t)green << 16) |
           ((uint32_t)red   <<  8) |
            (uint32_t)blue;
}

/* ------------------------------------------------------------------------- */
/* Temperature processing                                                    */
/* ------------------------------------------------------------------------- */

/**
 * @brief Convert raw ADC reading to Celsius, print it, and set LED colour.
 *
 * @param adc_sample_raw Raw 12-bit ADC value from the internal temperature sensor
 */
void update_temperature_state(uint32_t adc_sample_raw)
{
    float sensor_voltage = ((float)adc_sample_raw * ADC_REFERENCE_VOLTAGE) / ADC_MAX_COUNT;
    float temperature_c  = 27.0f - ((sensor_voltage - SENSOR_VOLTAGE_AT_27C) / SENSOR_SLOPE_V_PER_C);

    int32_t whole_part = (int32_t)temperature_c;
    int32_t frac_part  = (int32_t)((temperature_c - (float)whole_part) * 100.0f);
    if (frac_part < 0) {
        frac_part = -frac_part;
    }

    printf("Raw ADC: 0x%03X  |  Temperature: %ld.%02ld degC\n",
           (unsigned int)adc_sample_raw,
           (long)whole_part,
           (long)frac_part);

    if (temperature_c < TEMPERATURE_COLD_LIMIT) {
        ws2812_send(pack_ws2812_colour(0x00, 0x3F, 0x00));   /* Green */
    } else if (temperature_c < TEMPERATURE_HOT_LIMIT) {
        ws2812_send(pack_ws2812_colour(0x3F, 0x18, 0x00));   /* Orange */
    } else {
        ws2812_send(pack_ws2812_colour(0x3F, 0x00, 0x00));   /* Red */
    }
}

/* ------------------------------------------------------------------------- */
/* Main                                                                      */
/* ------------------------------------------------------------------------- */

int main(void)
{
    stdio_init_all();
    sleep_ms(5000);

    PIO pio_instance = WS2812_PIO_BLOCK;
    uint program_offset = pio_add_program(pio_instance, &ws2812_program);

    ws2812_program_init(
        pio_instance,
        WS2812_STATE_MACHINE,
        program_offset,
        WS2812_DATA_GPIO,
        800000,
        WS2812_USES_RGBW
    );

    ws2812_send(pack_ws2812_colour(0x00, 0x00, 0x00));

    printf("Lab 11 - Temperature Sensor and RGB LED\n");
    printf("Reading internal temperature every 1 second...\n");

    lab11_core();

    return 0;
}