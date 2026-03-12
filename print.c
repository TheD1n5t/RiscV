#include "print.h"
#include "uart.h"

static void print_digit(unsigned int x) {
    uart_putc((char)('0' + x));
}

static void print_hex_digit(unsigned int x) {
    x &= 0xF;
    if (x < 10) {
        uart_putc((char)('0' + x));
    } else {
        uart_putc((char)('A' + (x - 10)));
    }
}

void print_uint(unsigned int x) {
    unsigned int digit;
    int started = 0;

    digit = 0;
    while (x >= 1000000000U) {
        x -= 1000000000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 100000000U) {
        x -= 100000000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 10000000U) {
        x -= 10000000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 1000000U) {
        x -= 1000000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 100000U) {
        x -= 100000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 10000U) {
        x -= 10000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 1000U) {
        x -= 1000U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 100U) {
        x -= 100U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    digit = 0;
    while (x >= 10U) {
        x -= 10U;
        digit++;
    }
    if (digit || started) {
        print_digit(digit);
        started = 1;
    }

    print_digit(x);
}

void print_hex8(unsigned int x) {
    print_hex_digit((x >> 4) & 0xF);
    print_hex_digit(x & 0xF);
}

void print_hex32(unsigned int x) {
    print_hex_digit((x >> 28) & 0xF);
    print_hex_digit((x >> 24) & 0xF);
    print_hex_digit((x >> 20) & 0xF);
    print_hex_digit((x >> 16) & 0xF);
    print_hex_digit((x >> 12) & 0xF);
    print_hex_digit((x >> 8) & 0xF);
    print_hex_digit((x >> 4) & 0xF);
    print_hex_digit(x & 0xF);
}