# Specify the name of the executable.
add_executable(lab12)

# Specify the source files to be compiled.
target_sources(lab12 PRIVATE lab12.c lab12.S)

# Pull in commonly used features.
target_link_libraries(lab12 PRIVATE pico_stdlib)

# Create map/bin/hex file etc.
pico_add_extra_outputs(lab12)

# Add the URL via pico_set_program_url.
apps_auto_set_url(lab12)
