#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>

#include "pico/stdlib.h"
#include "pico/float.h"
#include "pico/double.h"
#include "pico/multicore.h"

/* Used to bit-cast a float to a 32-bit integer and back */
typedef union {
    float   f;
    int32_t i;
} float_int_cast_t;

/* Core 1 jobs must return a 32-bit integer */
typedef int32_t (*core1_job_t)(int32_t);

/* Prevent the compiler from moving code across timing boundaries */
static inline void compiler_barrier(void) {
    __asm volatile ("" ::: "memory");
}

/**
 * Calculate PI using Wallis' formula with single precision.
 * noinline helps stop the compiler from collapsing benchmark calls.
 */
__attribute__((noinline))
float calculateWallis_float(int iterations) {
    float result = 1.0f;

    for (int n = 1; n <= iterations; n++) {
        float numerator   = 4.0f * n * n;
        float denominator = (4.0f * n * n) - 1.0f;
        result *= (numerator / denominator);
    }

    return result * 2.0f;
}

/**
 * Calculate PI using Wallis' formula with double precision.
 */
__attribute__((noinline))
double calculateWallis_double(int iterations) {
    double result = 1.0;

    for (int n = 1; n <= iterations; n++) {
        double numerator   = 4.0 * n * n;
        double denominator = (4.0 * n * n) - 1.0;
        result *= (numerator / denominator);
    }

    return result * 2.0;
}

/**
 * Wrapper for Core 1 so that the return type is safely int32_t.
 * The float is returned as its raw 32-bit bit pattern.
 */
__attribute__((noinline))
int32_t calculateWallis_float_bits(int iterations) {
    float_int_cast_t cast;
    cast.f = calculateWallis_float(iterations);
    return cast.i;
}

/**
 * Core 1 dispatcher.
 * Receives:
 *   1) function pointer
 *   2) integer parameter
 * Executes the function and pushes the 32-bit result back.
 */
void core1_entry(void) {
    while (1) {
        uintptr_t raw_func = (uintptr_t)multicore_fifo_pop_blocking();
        int32_t p          = (int32_t)multicore_fifo_pop_blocking();

        core1_job_t func = (core1_job_t)raw_func;
        int32_t result   = func(p);

        multicore_fifo_push_blocking((uint32_t)result);
    }
}

int main(void) {
    /* volatile stops the compiler from treating the benchmark input as a fixed constant */
    volatile int iter_source = 100000;

    float  pi_float  = 0.0f;
    double pi_double = 0.0;

    uint64_t t_start, t_end;
    uint64_t t_float_start, t_float_end;
    uint64_t t_double_start, t_double_end;

    stdio_init_all();
    sleep_ms(5000);

    multicore_launch_core1(core1_entry);

    /* ---------------- Sequential run ---------------- */
    printf("\n--- Sequential Run (single core) ---\n");

    t_start = time_us_64();

    int seq_float_iters = iter_source;
    compiler_barrier();
    t_float_start = time_us_64();
    pi_float = calculateWallis_float(seq_float_iters);
    compiler_barrier();
    t_float_end = time_us_64();

    int seq_double_iters = iter_source;
    compiler_barrier();
    t_double_start = time_us_64();
    pi_double = calculateWallis_double(seq_double_iters);
    compiler_barrier();
    t_double_end = time_us_64();

    t_end = time_us_64();

    printf("Float  PI: %.10f  | Time: %llu us\n",
           pi_float,
           (unsigned long long)(t_float_end - t_float_start));

    printf("Double PI: %.10lf | Time: %llu us\n",
           pi_double,
           (unsigned long long)(t_double_end - t_double_start));

    printf("Total sequential time: %llu us\n",
           (unsigned long long)(t_end - t_start));

    /* ---------------- Parallel run ---------------- */
    printf("\n--- Parallel Run (dual core) ---\n");

    int par_float_iters  = iter_source;
    int par_double_iters = iter_source;

    t_start = time_us_64();

    /* Start float on Core 1 */
    multicore_fifo_push_blocking((uint32_t)(uintptr_t)&calculateWallis_float_bits);
    multicore_fifo_push_blocking((uint32_t)par_float_iters);

    /* Run double on Core 0 */
    compiler_barrier();
    t_double_start = time_us_64();
    pi_double = calculateWallis_double(par_double_iters);
    compiler_barrier();
    t_double_end = time_us_64();

    /* Collect float result from Core 1 */
    t_float_start = t_start;

    float_int_cast_t cast;
    cast.i = (int32_t)multicore_fifo_pop_blocking();
    t_float_end = time_us_64();
    pi_float = cast.f;

    t_end = time_us_64();

    printf("Float  PI: %.10f  | Core 1 finished at: %llu us\n",
           pi_float,
           (unsigned long long)(t_float_end - t_float_start));

    printf("Double PI: %.10lf | Core 0 time:        %llu us\n",
           pi_double,
           (unsigned long long)(t_double_end - t_double_start));

    printf("Total parallel time: %llu us\n",
           (unsigned long long)(t_end - t_start));

    return 0;
}