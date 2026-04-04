# CMakeLists.txt for Lab #11 – Reading Temperatures and Displaying Colours
#
# Changes from the template:
#   1. pico_generate_pio_header  – generates ws2812.pio.h at build time so
#                                  the C code can drive the WS2812 via PIO.
#   2. hardware_pio              – PIO library (needed for WS2812).
#   3. hardware_adc              – ADC library (needed for temperature sensor).
#   4. pico_enable_stdio_usb     – routes printf over USB CDC so output is
#                                  visible in the serial monitor.
#                                  THIS WAS THE REASON SERIAL WAS SILENT BEFORE.

# Specify the name of the executable.
add_executable(lab11)

# Specify the source files to be compiled.
target_sources(lab11 PRIVATE lab11.c lab11.S)

# Generate ws2812.pio.h from the shared PIO source file.
pico_generate_pio_header(lab11 ${CMAKE_SOURCE_DIR}/examples/ws2812_rgb/ws2812.pio)

# Link against required libraries.
target_link_libraries(lab11 PRIVATE
    pico_stdlib
    hardware_pio
    hardware_adc
)

# Route printf output over USB (not UART) so it appears in the serial monitor.
pico_enable_stdio_usb(lab11 1)

# Create map/bin/hex/uf2 output files.
pico_add_extra_outputs(lab11)

# Add the URL via pico_set_program_url.
apps_auto_set_url(lab11)