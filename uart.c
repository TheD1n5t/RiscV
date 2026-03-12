#include "uart.h"

#define UART ((volatile unsigned int *)0x40002000)

void uart_delay(void) {
    for (volatile int i = 0; i < 12000; i++) {
    }
}

void uart_putc(char c) {
    *UART = (unsigned int)c;
    uart_delay();
}

void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

void uart_newline(void) {
    uart_putc('\r');
    uart_putc('\n');
}