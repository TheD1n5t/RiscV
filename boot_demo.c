#include "uart.h"
#include "print.h"

int main(void) {
    unsigned int sum = 123U + 45U;

    uart_putc('B');
    uart_putc('o');
    uart_putc('o');
    uart_putc('t');
    uart_putc(' ');
    uart_putc('o');
    uart_putc('k');
    uart_putc(':');
    uart_newline();

    uart_putc('s');
    uart_putc('u');
    uart_putc('m');
    uart_putc(' ');
    uart_putc('=');
    uart_putc(' ');
    print_uint(sum);
    uart_newline();

    uart_putc('0');
    uart_putc('x');
    print_hex32(sum);
    uart_newline();

    while (1) {
    }

    return 0;
}
