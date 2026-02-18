#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "pico/stdlib.h"
#include "pico/float.h"     // Required for using single-precision variables.
#include "pico/double.h"    // Required for using double-precision variables.


float wallis_product(int iter) {
    float product = 1.0f; // Initialize the product to 1
    for (int n = 1; n <= iter; n++) {
        float term1 = (2.0f * n) / (2.0f * n - 1.0f); // First term: (2n)/(2n-1)
        float term2 =(2.0f * n) / (2.0f *n +1.0f); // Second term: (2n)/(2n+1)
        product *= term1 * term2; // Multiply the terms into the product
    }
    return product * 2.0f; // Multiply by 2 to approximate n
}

double wallis_product2(int iter) {
    double product = 1.0; // Initialize the product to 1
    for (int n = 1; n <= iter; n++) {
        double term1 = (2.0 * n) / (2.0 * n - 1.0); // First term: (2n)/(2n-1)
        double term2 =(2.0 * n) / (2.0 *n +1.0); // Second term: (2n)/(2n+1)
        product *= term1 * term2; // Multiply the terms into the product
    }
    return product * 2.0; // Multiply by 2 to approximate n
}

int main() {

    int iterations = 100000;
    float pi_ref = 3.14159265359;

    float pi_w = wallis_product(iterations);
    float float_error = pi_w - pi_ref;
    double pi_w2 = wallis_product2(iterations);
    double double_error = pi_w2 - pi_ref;

    printf("PI using wallis product (float): %.10f, ", pi_w);
    printf("approx error: %.10f\n", float_error);
    printf("PI using wallis product (double): %.10f, ", pi_w2);
    printf("approx error: %.10f\n", double_error);
        // Returning zero indicates everything went okay.
        return 0;
}