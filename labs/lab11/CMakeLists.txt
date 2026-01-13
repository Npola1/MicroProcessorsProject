# Specify the name of the executable.
add_executable(lab11)

# Specify the source files to be compiled.
target_sources(lab11 PRIVATE lab11.c lab11.S)

# Pull in commonly used features.
target_link_libraries(lab11 PRIVATE pico_stdlib)

# Create map/bin/hex file etc.
pico_add_extra_outputs(lab11)

# Add the URL via pico_set_program_url.
apps_auto_set_url(lab11)
