# pico-apps

Template code repository for the Raspberry Pi Pico used for the CSU23021 course for the Spring semester, and so on. Students should clone this repository to their own Git area and use it as the basis to complete their assignments and labs throughout the year.

This repository is set up for use with Visual Studio Code, CMAKE and Doxygen. All build collateral output will be generated under the "build" folder and all Doxygen-generated documentation will be generated under the "docs" folder. The repository is structured as follows.

## assignments

Top-level folder containing skeleton project templates for the three coding assignments.

### assignments/assign01

Skeleton template for assignment #01.

### assignments/assign02

Skeleton template for assignment #02.

## examples

Top-level folder containing all example projects.

### examples/blink_asm

An assembly-based application that flashes the built-in LED of the Pi Pico board using subroutines with the delay between LED toggles set using a CPU sleep command.

### examples/blink_c

A C-based application that flashes the built-in LED of the Pi Pico board with the delay between LED toggles set using a CPU sleep command.

### examples/blink_svc

An assembly-based application that flashes the built-in LED of the Pi Pico board using SVC exception handlers with the delay between LED toggles set using a CPU sleep command.

### examples/hello_c

A C-based application that uses UART0 to print a "Hello World!" message to the console.

### examples/multi_c

A C-based application that uses both CPU cores to calculate factorial and Fibonacci sequences and display the results to the console.

### examples/ws2812_rgb

A C-based application that uses PIO to alternately flash the NeoPixel on the MAKER-PI-PICO board red, green then blue in a continuous loop.

## labs

Top-level folder containing skeleton project templates for the ten lab exercises.

### labs/lab01

Skeleton template for lab exercise #01.

### labs/lab02

Skeleton template for lab exercise #02.

### labs/lab03

Skeleton template for lab exercise #03.

### labs/lab04

Skeleton template for lab exercise #04.

### labs/lab05

Skeleton template for lab exercise #05.

### labs/lab06

Skeleton template for lab exercise #06.

### labs/lab07

Skeleton template for lab exercise #07.

### labs/lab08

Skeleton template for lab exercise #08.

### labs/lab09

Skeleton template for lab exercise #09.

### labs/lab10

Skeleton template for lab exercise #10.

### labs/lab11

Skeleton template for lab exercise #11.

### labs/lab12

Skeleton template for lab exercise #12.
