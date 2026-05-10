library ieee;
use ieee.std_logic_1164.all;

entity riscv_soc_boot_top is
  generic(
    CLK_FREQ_HZ    : integer := 50_000_000;
    BAUD           : integer := 115200;
    IMEM_WORDS     : integer := 4096;
    G_FAULT_INJECT : boolean := false;
    G_PC_TMR       : boolean := true;
    G_STATE_TMR    : boolean := true;
    G_RF_TMR       : boolean := true;
    G_RF_SELF_HEAL : boolean := true;
    G_IMEM_ECC     : boolean := true;
    G_DMEM_ECC     : boolean := true
  );
  port(
    clk       : in  std_logic;
    reset     : in  std_logic;
    uart_rx_i : in  std_logic;
    uart_tx_o : out std_logic;
    led0_o    : out std_logic;
    status_o  : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of riscv_soc_boot_top is

  signal boot_done              : std_logic;
  signal boot_error             : std_logic;
  signal prog_we                : std_logic;
  signal prog_addr              : std_logic_vector(31 downto 0);
  signal prog_wdata             : std_logic_vector(31 downto 0);
  signal imem_pc                : std_logic_vector(31 downto 0);
  signal dmem_we                : std_logic;
  signal dmem_addr              : std_logic_vector(31 downto 0);
  signal dmem_wdata             : std_logic_vector(31 downto 0);
  signal pc_tmr_error           : std_logic;
  signal state_tmr_error        : std_logic;
  signal regfile_tmr_error      : std_logic;
  signal dmem_ecc_single_error  : std_logic;
  signal dmem_ecc_double_error  : std_logic;
  signal imem_ecc_single_error  : std_logic;
  signal imem_ecc_double_error  : std_logic;
  signal status                 : std_logic_vector(15 downto 0);

  attribute dont_touch : string;
  attribute dont_touch of boot_done             : signal is "true";
  attribute dont_touch of boot_error            : signal is "true";
  attribute dont_touch of imem_pc               : signal is "true";
  attribute dont_touch of dmem_addr             : signal is "true";
  attribute dont_touch of status                : signal is "true";
  attribute keep : string;
  attribute keep of status : signal is "true";

begin

  u_soc : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ    => CLK_FREQ_HZ,
      BAUD           => BAUD,
      IMEM_WORDS     => IMEM_WORDS,
      G_FAULT_INJECT => G_FAULT_INJECT,
      G_PC_TMR       => G_PC_TMR,
      G_STATE_TMR    => G_STATE_TMR,
      G_RF_TMR       => G_RF_TMR,
      G_RF_SELF_HEAL => G_RF_SELF_HEAL,
      G_IMEM_ECC     => G_IMEM_ECC,
      G_DMEM_ECC     => G_DMEM_ECC
    )
    port map(
      clk       => clk,
      reset     => reset,
      uart_rx_i => uart_rx_i,
      uart_tx_o => uart_tx_o,
      led0_o    => led0_o,

      boot_done_o  => boot_done,
      boot_error_o => boot_error,
      prog_we_o    => prog_we,
      prog_addr_o  => prog_addr,
      prog_wdata_o => prog_wdata,
      imem_pc_o    => imem_pc,
      dmem_we_o    => dmem_we,
      dmem_addr_o  => dmem_addr,
      dmem_wdata_o => dmem_wdata,

      ext_prog_mode_i  => '0',
      ext_cpu_enable_i => '0',
      ext_imem_we_i    => '0',
      ext_imem_addr_i  => (others => '0'),
      ext_imem_wdata_i => (others => '0'),
      ext_dmem_we_i    => '0',
      ext_dmem_addr_i  => (others => '0'),
      ext_dmem_wdata_i => (others => '0'),

      fi_pc_mask_i      => (others => '0'),
      fi_pc_target_i    => "00",
      fi_pc_strobe_i    => '0',
      fi_state_mask_i   => (others => '0'),
      fi_state_target_i => "00",
      fi_state_strobe_i => '0',
      fi_dmem_mask_i    => (others => '0'),
      fi_dmem_addr_i    => (others => '0'),
      fi_dmem_strobe_i  => '0',
      fi_rf_mask_i      => (others => '0'),
      fi_rf_addr_i      => (others => '0'),
      fi_rf_target_i    => "00",
      fi_rf_strobe_i    => '0',
      fi_imem_mask_i    => (others => '0'),
      fi_imem_addr_i    => (others => '0'),
      fi_imem_strobe_i  => '0',

      pc_tmr_error_o          => pc_tmr_error,
      state_tmr_error_o       => state_tmr_error,
      regfile_tmr_error_o     => regfile_tmr_error,
      dmem_ecc_single_error_o => dmem_ecc_single_error,
      dmem_ecc_double_error_o => dmem_ecc_double_error,
      imem_ecc_single_error_o => imem_ecc_single_error,
      imem_ecc_double_error_o => imem_ecc_double_error
    );

  status <= imem_pc(3 downto 0) &
            dmem_addr(3 downto 0) &
            imem_ecc_double_error &
            imem_ecc_single_error &
            dmem_ecc_double_error &
            dmem_ecc_single_error &
            regfile_tmr_error &
            state_tmr_error &
            pc_tmr_error &
            boot_error;

  status_o(15 downto 1) <= status(15 downto 1);
  status_o(0)           <= status(0) or boot_done or prog_we or dmem_we or prog_addr(0) or
                           prog_wdata(0) or dmem_wdata(0);

end architecture;
