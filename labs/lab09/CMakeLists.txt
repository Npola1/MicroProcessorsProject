# Specify the name of the executable.
add_executable(lab09)

# Specify the source files to be compiled.
target_sources(lab09 PRIVATE lab09.c lab09.S)

# Pull in commonly used features.
target_link_libraries(lab09 PRIVATE
    pico_stdlib
    pico_float
    pico_double
    pico_multicore
)

# Create map/bin/hex file etc.
pico_add_extra_outputs(lab09)

pico_enable_stdio_usb(lab09 1)

# Add the URL via pico_set_program_url.
apps_auto_set_url(lab09)