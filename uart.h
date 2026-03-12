#ifndef UART_H
#define UART_H

void uart_delay(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_newline(void);

#endif