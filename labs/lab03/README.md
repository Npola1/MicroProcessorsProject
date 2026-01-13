# LAB03 NOTES

See [LAB #03] on the module Blackboard site for details of this lab.

Example code for this lab has been tested on both the Raspberry Pi Pico hardware platform as well as the Woki online simulator for the Raspberry Pi Pico. There are some differences between using the Wokwi online simulator and the real Raspberry Pi Pico hardware however.

If using the simulator, the `pico/stdlib` include and the `stdio_uart_init()` function need to be commented out from the `lab03.c` file in order for the code to compile cleanly. The `wokwi-pi-pico` component environment option in the `diagram.json` file may also need to be set to use `arduino-community` for the code to work correctly (proably a quirk of the simulator).

To run the demo on the simulator, rename the default `sketch.ino` file to be called `lab03.c` and overwrite the default content with the content of the `lab03.c` file in this repository. Also, make sure to update the `diagram.json` (but do not change the name).
