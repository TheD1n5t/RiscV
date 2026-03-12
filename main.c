#include "uart.h"
#include "print.h"

int a = 123;
int b = 45;
int sum = 0;

const char msg[] = "Hello from C framework!";

int main(void) {
    sum = a + b;

    uart_puts(msg);
    uart_newline();

    uart_puts("sum = ");
    print_uint((unsigned int)sum);
    uart_newline();

    uart_puts("sum hex = 0x");
    print_hex32((unsigned int)sum);
    uart_newline();

    while (1) {
    }

    return 0;
}