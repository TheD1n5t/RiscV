#include <stdio.h>
#include <stdint.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

#define RISCV_AXI_BASE XPAR_RISCV_SOC_AXI_WRAPPER_0_BASEADDR

#define REG_CONTROL             0x00U
#define REG_STATUS              0x04U
#define REG_IMEM_PC             0x18U
#define REG_LAST_DMEM_ADDR      0x1CU
#define REG_LAST_DMEM_DATA      0x20U
#define REG_UART_INJECT_DATA    0x24U
#define REG_UART_INJECT_STATUS  0x28U

#define CTRL_SOFT_RESET         (1U << 1)
#define CTRL_CLEAR_STATUS       (1U << 4)
#define CTRL_UART_BOOT_MODE     (1U << 6)

#define STATUS_BOOT_DONE        (1U << 1)
#define STATUS_PASS_SEEN        (1U << 3)
#define STATUS_FAIL_SEEN        (1U << 4)
#define STATUS_BOOT_ERROR       (1U << 6)
#define STATUS_UART_BOOT_MODE   (1U << 7)

#define UART_INJ_BUSY           (1U << 0)

#define PASS_ADDR               0x00001000U
#define PASS_VALUE              0x00000001U

#define POLL_ITERS              400
#define POLL_DELAY_US           50000

typedef struct {
    const char *name;
    const uint32_t *imem_words;
    uint32_t imem_word_count;
    const uint32_t *dmem_words;
    uint32_t dmem_word_count;
} riscv_boot_test_t;

static const uint32_t pass_from_imem_words[] = {
    0x00001FB7U, /* lui  x31, 0x1       ; x31 = 0x1000 */
    0x00100093U, /* addi x1,  x0, 1      ; pass value */
    0x001FA023U, /* sw   x1,  0(x31)     ; write pass marker */
    0x0000006FU  /* jal  x0,  0          ; stop */
};

static const uint32_t pass_from_dmem_words[] = {
    0x00002083U, /* lw   x1,  0(x0)      ; load preloaded pass value */
    0x00001FB7U, /* lui  x31, 0x1        ; x31 = 0x1000 */
    0x001FA023U, /* sw   x1,  0(x31)     ; write pass marker */
    0x0000006FU  /* jal  x0,  0          ; stop */
};

static const uint32_t pass_from_dmem_data[] = {
    PASS_VALUE
};

static const riscv_boot_test_t tests[] = {
    {
        "UART_BOOT_IMEM_ONLY",
        pass_from_imem_words,
        sizeof(pass_from_imem_words) / sizeof(pass_from_imem_words[0]),
        NULL,
        0
    },
    {
        "UART_BOOT_WITH_DMEM_PRELOAD",
        pass_from_dmem_words,
        sizeof(pass_from_dmem_words) / sizeof(pass_from_dmem_words[0]),
        pass_from_dmem_data,
        sizeof(pass_from_dmem_data) / sizeof(pass_from_dmem_data[0])
    }
};

static inline void reg_write(uint32_t off, uint32_t val) {
    Xil_Out32(RISCV_AXI_BASE + off, val);
}

static inline uint32_t reg_read(uint32_t off) {
    return Xil_In32(RISCV_AXI_BASE + off);
}

static void control_set(uint32_t value) {
    reg_write(REG_CONTROL, value);
    usleep(1000);
}

static void control_pulse(uint32_t base_bits, uint32_t pulse_bits) {
    reg_write(REG_CONTROL, base_bits | pulse_bits);
    usleep(1000);
    reg_write(REG_CONTROL, base_bits);
    usleep(1000);
}

static int wait_uart_inject_idle(void) {
    for (uint32_t i = 0; i < 1000000U; i++) {
        if ((reg_read(REG_UART_INJECT_STATUS) & UART_INJ_BUSY) == 0U) {
            return 1;
        }

        usleep(1);
    }

    return 0;
}

static int uart_inject_byte(uint8_t byte) {
    if (!wait_uart_inject_idle()) {
        return 0;
    }

    reg_write(REG_UART_INJECT_DATA, (uint32_t)byte);

    if (!wait_uart_inject_idle()) {
        return 0;
    }

    return 1;
}

static int send_byte(uint8_t byte, uint32_t *sent_count) {
    if (!uart_inject_byte(byte)) {
        xil_printf("ERROR: UART injector timeout at image byte %lu\r\n",
                   (unsigned long)*sent_count);
        return 0;
    }

    *sent_count = *sent_count + 1U;
    return 1;
}

static int send_u32_le(uint32_t value, uint32_t *sent_count) {
    if (!send_byte((uint8_t)(value >> 0), sent_count)) {
        return 0;
    }

    if (!send_byte((uint8_t)(value >> 8), sent_count)) {
        return 0;
    }

    if (!send_byte((uint8_t)(value >> 16), sent_count)) {
        return 0;
    }

    if (!send_byte((uint8_t)(value >> 24), sent_count)) {
        return 0;
    }

    return 1;
}

static int send_boot_image(const riscv_boot_test_t *test) {
    uint32_t sent_count = 0;
    uint32_t imem_len_bytes = test->imem_word_count * 4U;
    uint32_t dmem_len_bytes = test->dmem_word_count * 4U;

    if (!send_byte(0x55U, &sent_count)) {
        return 0;
    }

    if (!send_byte(0xAAU, &sent_count)) {
        return 0;
    }

    if (!send_u32_le(imem_len_bytes, &sent_count)) {
        return 0;
    }

    if (!send_u32_le(dmem_len_bytes, &sent_count)) {
        return 0;
    }

    for (uint32_t i = 0; i < test->imem_word_count; i++) {
        if (!send_u32_le(test->imem_words[i], &sent_count)) {
            return 0;
        }
    }

    for (uint32_t i = 0; i < test->dmem_word_count; i++) {
        if (!send_u32_le(test->dmem_words[i], &sent_count)) {
            return 0;
        }
    }

    xil_printf("Sent boot image bytes: %lu\r\n", (unsigned long)sent_count);
    return 1;
}

static int enter_uart_boot_mode(void) {
    uint32_t status;

    control_set(CTRL_UART_BOOT_MODE);
    control_pulse(CTRL_UART_BOOT_MODE, CTRL_SOFT_RESET);
    control_pulse(CTRL_UART_BOOT_MODE, CTRL_CLEAR_STATUS);

    status = reg_read(REG_STATUS);

    if ((status & STATUS_UART_BOOT_MODE) == 0U) {
        xil_printf("ERROR: uart_boot_mode status bit is not set, STATUS=0x%08lx\r\n",
                   (unsigned long)status);
        return 0;
    }

    return 1;
}

static int wait_for_test_result(const char *name) {
    uint32_t status = 0;
    uint32_t pc = 0;
    uint32_t last_addr = 0;
    uint32_t last_data = 0;

    for (uint32_t i = 0; i < POLL_ITERS; i++) {
        status    = reg_read(REG_STATUS);
        pc        = reg_read(REG_IMEM_PC);
        last_addr = reg_read(REG_LAST_DMEM_ADDR);
        last_data = reg_read(REG_LAST_DMEM_DATA);

        if ((i < 5U) || ((i % 20U) == 0U)) {
            xil_printf("[%s %03lu] STATUS=0x%08lx PC=0x%08lx LAST_ADDR=0x%08lx LAST_DATA=0x%08lx\r\n",
                       name,
                       (unsigned long)i,
                       (unsigned long)status,
                       (unsigned long)pc,
                       (unsigned long)last_addr,
                       (unsigned long)last_data);
        }

        if ((status & STATUS_BOOT_ERROR) != 0U) {
            xil_printf("%s: FAIL boot_error\r\n", name);
            return -1;
        }

        if ((status & STATUS_FAIL_SEEN) != 0U) {
            xil_printf("%s: FAIL marker seen\r\n", name);
            return -1;
        }

        if ((status & STATUS_PASS_SEEN) != 0U) {
            if (last_addr == PASS_ADDR && last_data == PASS_VALUE) {
                xil_printf("%s: PASS\r\n", name);
                return 1;
            }

            xil_printf("%s: FAIL unexpected pass marker data\r\n", name);
            return -1;
        }

        if (((status & STATUS_BOOT_DONE) != 0U) &&
            (last_addr == PASS_ADDR) &&
            (last_data == PASS_VALUE)) {
            xil_printf("%s: PASS\r\n", name);
            return 1;
        }

        usleep(POLL_DELAY_US);
    }

    xil_printf("%s: TIMEOUT\r\n", name);
    xil_printf("FINAL STATUS=0x%08lx PC=0x%08lx LAST_ADDR=0x%08lx LAST_DATA=0x%08lx\r\n",
               (unsigned long)status,
               (unsigned long)pc,
               (unsigned long)last_addr,
               (unsigned long)last_data);

    return 0;
}

static int run_uart_boot_test(const riscv_boot_test_t *test) {
    xil_printf("\r\n===== %s =====\r\n", test->name);
    xil_printf("IMEM words: %lu\r\n", (unsigned long)test->imem_word_count);
    xil_printf("DMEM words: %lu\r\n", (unsigned long)test->dmem_word_count);

    if (!enter_uart_boot_mode()) {
        return -1;
    }

    if (!send_boot_image(test)) {
        return -1;
    }

    return wait_for_test_result(test->name);
}

int main(void) {
    uint32_t pass_count = 0;
    uint32_t fail_count = 0;
    uint32_t timeout_count = 0;

    xil_printf("\r\n===== RISC-V UART BOOT IMAGE RUNNER =====\r\n");
    xil_printf("AXI base: 0x%08lx\r\n", (unsigned long)RISCV_AXI_BASE);
    xil_printf("Tests   : %lu\r\n", (unsigned long)(sizeof(tests) / sizeof(tests[0])));

    for (uint32_t i = 0; i < (sizeof(tests) / sizeof(tests[0])); i++) {
        int result = run_uart_boot_test(&tests[i]);

        if (result > 0) {
            pass_count++;
        } else if (result < 0) {
            fail_count++;
        } else {
            timeout_count++;
        }
    }

    xil_printf("\r\n========================================\r\n");
    xil_printf("SUMMARY\r\n");
    xil_printf("PASS    : %lu\r\n", (unsigned long)pass_count);
    xil_printf("FAIL    : %lu\r\n", (unsigned long)fail_count);
    xil_printf("TIMEOUT : %lu\r\n", (unsigned long)timeout_count);
    xil_printf("TOTAL   : %lu\r\n",
               (unsigned long)(sizeof(tests) / sizeof(tests[0])));
    xil_printf("========================================\r\n");

    while (1) {}
    return 0;
}
