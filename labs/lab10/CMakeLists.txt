# Specify the name of the executable.
add_executable(lab10)

# Specify the source files to be compiled.
target_sources(lab10 PRIVATE lab10.c)

# Pull in commonly used features.
target_link_libraries(lab10 PRIVATE
    pico_stdlib
    pico_float
    pico_double
    pico_multicore
    hardware_structs     # provides xip_ctrl_hw (xip_ctrl.h)
)

# Create map/bin/hex file etc.
pico_add_extra_outputs(lab10)

pico_enable_stdio_usb(lab10 1)

# Add the URL via pico_set_program_url.
apps_auto_set_url(lab10)
