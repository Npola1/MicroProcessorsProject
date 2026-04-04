/**
 * @file    lab10.c
 * @brief   Lab #10 – Decelerating Applications by Disabling Caching
 *
 * Extends Lab #09 (dual-core Wallis PI approximation) to benchmark the
 * RP2040 XIP (execute-in-place) cache across four scenarios:
 *
 *  1. Single core,  cache ENABLED
 *  2. Single core,  cache DISABLED
 *  3. Dual  cores,  cache ENABLED
 *  4. Dual  cores,  cache DISABLED
 *
 * For every scenario three data-points are captured:
 *  - Execution time of the single-precision  (float)  Wallis function
 *  - Execution time of the double-precision  (double) Wallis function
 *  - Total wall-clock time for that scenario
 *
 * XIP cache control is achieved by reading/writing bit 0 (EN) of the
 * XIP CTRL register, which is located at XIP_CTRL_BASE + 0x00 and is
 * exposed by the Pico SDK as xip_ctrl_hw->ctrl.
 *
 * @note    The program flushes the cache whenever it is re-enabled so
 *          that stale lines from the previous run do not inflate the
 *          "cache-enabled" timing.
 *
 * @author  [Your Name]
 * @date    2025/2026
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

#include "pico/stdlib.h"
#include "pico/float.h"
#include "pico/double.h"
#include "pico/multicore.h"
#include "hardware/structs/xip_ctrl.h"   /* xip_ctrl_hw, XIP_CTRL_EN_BITS   */
#include "hardware/regs/xip.h"           /* XIP_STAT_FLUSH_READY_BITS        */


/* -----------------------------------------------------------------------
 * Union used to safely bit-cast between float and int32_t.
 * Both are 32-bit types so the IEEE-754 bit pattern is preserved exactly.
 * ----------------------------------------------------------------------- */
typedef union {
    float   f;
    int32_t i;
} float_int_cast_t;


/* =========================================================================
 * XIP CACHE CONTROL HELPERS
 * =========================================================================
 *
 * RP2040 Datasheet, Section 2.6 – XIP CTRL Register (offset 0x00):
 *   Bit 0  EN  – When 1, cache lookups are performed for cacheable
 *                XIP accesses.  When 0, all XIP reads bypass the cache
 *                and go directly to flash.
 *
 * The Pico SDK exposes the register as  xip_ctrl_hw->ctrl  and defines
 * the bit-mask as  XIP_CTRL_EN_BITS  (== 1u << 0).
 * ========================================================================= */

/**
 * @brief  Read the current enable state of the XIP cache.
 *
 * Reads bit 0 (EN) of the XIP CTRL register.
 *
 * @return  true  if the cache is currently enabled,
 *          false if the cache is currently disabled.
 */
bool get_xip_cache_en(void) {
    return (xip_ctrl_hw->ctrl & XIP_CTRL_EN_BITS) != 0u;
}


/**
 * @brief  Set the enable state of the XIP cache.
 *
 * Writes bit 0 (EN) of the XIP CTRL register.
 *
 * When re-enabling the cache the function also flushes it so that no
 * stale tag/data from the previous (cache-off) period appears as a hit
 * and biases the measurement.  The flush is performed by writing 1 to
 * the FLUSH register and polling XIP_STAT_FLUSH_READY_BITS.
 *
 * @param  cache_en  true to enable the cache, false to disable it.
 * @return           The previous enable state (before this call).
 */
bool set_xip_cache_en(bool cache_en) {
    bool prev = get_xip_cache_en();

    if (cache_en) {
        /* Enable cache first, then flush so the cache starts cold/clean. */
        hw_set_bits(&xip_ctrl_hw->ctrl, XIP_CTRL_EN_BITS);

        /* Trigger a full cache flush and wait for completion (~1024 cycles). */
        xip_ctrl_hw->flush = 1u;
        while (!(xip_ctrl_hw->stat & XIP_STAT_FLUSH_READY_BITS)) {
            tight_loop_contents();
        }
    } else {
        /* Clear the EN bit – subsequent XIP accesses bypass the cache. */
        hw_clear_bits(&xip_ctrl_hw->ctrl, XIP_CTRL_EN_BITS);
    }

    return prev;
}


/* =========================================================================
 * WALLIS PI APPROXIMATION FUNCTIONS
 * =========================================================================
 *
 * Both functions compute  PI  using Wallis' infinite product:
 *
 *   PI/2 = (2/1)·(2/3)·(4/3)·(4/5)·(6/5)·(6/7)· ...
 *
 * which may be rewritten per iteration n (1-based) as:
 *
 *   product *= 4n² / (4n² − 1)
 *
 *   PI ≈ 2 · product
 * ========================================================================= */

/**
 * @brief  Approximate PI using Wallis' formula in single precision.
 *
 * Uses 32-bit IEEE-754 floating-point arithmetic (hardware FPU on M0+
 * when the pico_float library is linked).
 *
 * @param  iterations  Number of product terms to accumulate.
 * @return             Approximation of PI as a float.
 */
float calculateWallis_float(int iterations) {
    float result = 1.0f;
    for (int n = 1; n <= iterations; n++) {
        float numerator   = 4.0f * (float)n * (float)n;
        float denominator = numerator - 1.0f;
        result *= numerator / denominator;
    }
    return result * 2.0f;
}


/**
 * @brief  Approximate PI using Wallis' formula in double precision.
 *
 * Uses 64-bit IEEE-754 floating-point arithmetic (software emulation on
 * M0+ when the pico_double library is linked).
 *
 * @param  iterations  Number of product terms to accumulate.
 * @return             Approximation of PI as a double.
 */
double calculateWallis_double(int iterations) {
    double result = 1.0;
    for (int n = 1; n <= iterations; n++) {
        double numerator   = 4.0 * (double)n * (double)n;
        double denominator = numerator - 1.0;
        result *= numerator / denominator;
    }
    return result * 2.0;
}


/* =========================================================================
 * CORE 1 ENTRY POINT
 * =========================================================================
 *
 * Core 1 sits in a loop waiting for two words on the inter-core FIFO:
 *   1. A function pointer  int32_t (*func)(int)
 *   2. An integer argument  p
 *
 * It calls func(p) and pushes the int32_t result back so Core 0 can
 * collect it.  For calculateWallis_float() the float return value is
 * reinterpreted as int32_t via the float_int_cast_t union on both sides.
 * ========================================================================= */

/**
 * @brief  Dispatcher loop executed on CPU Core 1.
 *
 * Waits for a function pointer and an integer parameter via the
 * inter-core FIFO, executes the function, and returns the result.
 */
void core1_entry(void) {
    while (true) {
        /* Pop the function pointer then the argument. */
        int32_t (*func)(int) = (int32_t (*)(int)) multicore_fifo_pop_blocking();
        int32_t p            = multicore_fifo_pop_blocking();

        /* Execute and push the result back to Core 0. */
        int32_t result = func(p);
        multicore_fifo_push_blocking(result);
    }
}


/* =========================================================================
 * BENCHMARK HELPERS
 * =========================================================================
 *
 * Two inline helper functions keep the main() body readable:
 *   run_sequential()  – both Wallis functions on Core 0 back-to-back.
 *   run_parallel()    – float on Core 1, double on Core 0 simultaneously.
 * ========================================================================= */

/**
 * @brief  Run both Wallis functions sequentially on Core 0 and print
 *         individual and total execution times.
 *
 * @param  iter      Number of Wallis iterations.
 * @param  label     Human-readable scenario label for the output.
 */
static void run_sequential(int iter, const char *label) {
    float    pi_float;
    double   pi_double;
    uint64_t t_start, t_end;
    uint64_t t_float_start, t_float_end;
    uint64_t t_double_start, t_double_end;

    printf("\n--- %s | Sequential (single core) ---\n", label);

    t_start = time_us_64();

    t_float_start = time_us_64();
    pi_float      = calculateWallis_float(iter);
    t_float_end   = time_us_64();

    t_double_start = time_us_64();
    pi_double      = calculateWallis_double(iter);
    t_double_end   = time_us_64();

    t_end = time_us_64();

    printf("  Float  PI : %.10f   | Time: %llu us\n",
           pi_float,  t_float_end  - t_float_start);
    printf("  Double PI : %.10lf  | Time: %llu us\n",
           pi_double, t_double_end - t_double_start);
    printf("  Total     :              %llu us\n", t_end - t_start);
}


/**
 * @brief  Run both Wallis functions in parallel (float on Core 1, double
 *         on Core 0) and print individual and total execution times.
 *
 * Core 1 must already be running core1_entry() before this is called.
 *
 * @param  iter      Number of Wallis iterations.
 * @param  label     Human-readable scenario label for the output.
 */
static void run_parallel(int iter, const char *label) {
    float    pi_float;
    double   pi_double;
    uint64_t t_start, t_end;
    uint64_t t_float_start, t_float_end;
    uint64_t t_double_start, t_double_end;
    float_int_cast_t cast;

    printf("\n--- %s | Parallel  (dual  core) ---\n", label);

    t_start = time_us_64();

    /* Dispatch float calculation to Core 1 – it begins immediately. */
    multicore_fifo_push_blocking((uintptr_t) &calculateWallis_float);
    multicore_fifo_push_blocking((int32_t)   iter);

    /* Run double on Core 0 concurrently with Core 1. */
    t_double_start = time_us_64();
    pi_double      = calculateWallis_double(iter);
    t_double_end   = time_us_64();

    /*
     * Core 1 started at t_start (same moment we dispatched).
     * Block here until it pushes the float result back.
     */
    t_float_start = t_start;
    cast.i        = multicore_fifo_pop_blocking();
    t_float_end   = time_us_64();
    pi_float      = cast.f;

    t_end = time_us_64();

    printf("  Float  PI : %.10f   | Core 1 time: %llu us\n",
           pi_float,  t_float_end  - t_float_start);
    printf("  Double PI : %.10lf  | Core 0 time: %llu us\n",
           pi_double, t_double_end - t_double_start);
    printf("  Total     :              %llu us\n", t_end - t_start);
}


/* =========================================================================
 * MAIN
 * =========================================================================
 *
 * Runs all four benchmark scenarios in order:
 *   Scenario 1 – single core, cache enabled
 *   Scenario 2 – single core, cache disabled
 *   Scenario 3 – dual  core, cache enabled
 *   Scenario 4 – dual  core, cache disabled
 *
 * The XIP cache state is restored to enabled between scenarios that
 * require it, and a separator line is printed to make the serial output
 * easy to copy into the results file.
 * ========================================================================= */

/**
 * @brief  Application entry point – executed on CPU Core 0.
 *
 * Initialises peripherals, launches the Core 1 dispatcher, then runs the
 * four cache/core benchmark scenarios and prints results over USB-CDC.
 *
 * @return  0 on success (never actually reached on RP2040).
 */
int main(void) {
    const int ITER_MAX = 100000;

    stdio_init_all();
    sleep_ms(5000);  /* Allow time for a serial monitor to connect. */

    /* Launch the Core 1 dispatcher once; it loops forever. */
    multicore_launch_core1(core1_entry);

    printf("=============================================================\n");
    printf("  Lab #10 – XIP Cache Impact Benchmark\n");
    printf("  Wallis iterations per function: %d\n", ITER_MAX);
    printf("=============================================================\n");

    /* ------------------------------------------------------------------ */
    /* Scenario 1 – single core, cache ENABLED (default boot state)       */
    /* ------------------------------------------------------------------ */
    set_xip_cache_en(true);
    printf("\n[Cache: ENABLED]  status = %d\n", get_xip_cache_en());
    run_sequential(ITER_MAX, "Cache ON ");

    /* ------------------------------------------------------------------ */
    /* Scenario 2 – single core, cache DISABLED                           */
    /* ------------------------------------------------------------------ */
    set_xip_cache_en(false);
    printf("\n[Cache: DISABLED] status = %d\n", get_xip_cache_en());
    run_sequential(ITER_MAX, "Cache OFF");

    /* ------------------------------------------------------------------ */
    /* Scenario 3 – dual core, cache ENABLED                              */
    /* ------------------------------------------------------------------ */
    set_xip_cache_en(true);
    printf("\n[Cache: ENABLED]  status = %d\n", get_xip_cache_en());
    run_parallel(ITER_MAX, "Cache ON ");

    /* ------------------------------------------------------------------ */
    /* Scenario 4 – dual core, cache DISABLED                             */
    /* ------------------------------------------------------------------ */
    set_xip_cache_en(false);
    printf("\n[Cache: DISABLED] status = %d\n", get_xip_cache_en());
    run_parallel(ITER_MAX, "Cache OFF");

    /* Restore the cache to enabled as a courtesy before exit. */
    set_xip_cache_en(true);

    printf("\n=============================================================\n");
    printf("  Benchmark complete.\n");
    printf("=============================================================\n");

    return 0;
}