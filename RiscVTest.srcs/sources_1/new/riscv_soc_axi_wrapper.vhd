library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity riscv_soc_axi_wrapper is
    Port (
        S_AXI_ACLK     : in  STD_LOGIC;
        S_AXI_ARESETN  : in  STD_LOGIC;

        -- AXI Write Channel
        S_AXI_AWADDR   : in  STD_LOGIC_VECTOR(31 downto 0);
        S_AXI_AWVALID  : in  STD_LOGIC;
        S_AXI_AWREADY  : out STD_LOGIC;
        S_AXI_WDATA    : in  STD_LOGIC_VECTOR(31 downto 0);
        S_AXI_WSTRB    : in  STD_LOGIC_VECTOR(3 downto 0);
        S_AXI_WVALID   : in  STD_LOGIC;
        S_AXI_WREADY   : out STD_LOGIC;
        S_AXI_BRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_BVALID   : out STD_LOGIC;
        S_AXI_BREADY   : in  STD_LOGIC;

        -- AXI Read Channel
        S_AXI_ARADDR   : in  STD_LOGIC_VECTOR(31 downto 0);
        S_AXI_ARVALID  : in  STD_LOGIC;
        S_AXI_ARREADY  : out STD_LOGIC;
        S_AXI_RDATA    : out STD_LOGIC_VECTOR(31 downto 0);
        S_AXI_RRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_RVALID   : out STD_LOGIC;
        S_AXI_RREADY   : in  STD_LOGIC;

        -- Optional debug outputs
        uart_tx_o      : out STD_LOGIC;
        led0_o         : out STD_LOGIC
    );
end riscv_soc_axi_wrapper;

architecture Behavioral of riscv_soc_axi_wrapper is

    ----------------------------------------------------------------------------
    -- Register map
    --
    -- 0x00 CONTROL
    --   bit 0 : cpu_enable      (level)
    --   bit 1 : soft_reset      (pulse on write = 1)
    --   bit 2 : imem_write      (pulse on write = 1)
    --   bit 3 : dmem_write      (pulse on write = 1)
    --   bit 4 : clear_status    (pulse on write = 1)
    --   bit 5 : prog_mode       (level)
    --   bit 6 : reserved
    --
    -- 0x04 STATUS
    --   bit 0 : cpu_enable
    --   bit 1 : boot_done
    --   bit 2 : last_dmem_we
    --   bit 3 : pass_seen
    --   bit 4 : fail_seen
    --   bit 5 : prog_mode
    --   bit 6 : boot_error
    --   bit 7 : reserved
    --   bit 8 : uart_inject_busy
    --
    -- 0x08 IMEM_ADDR   (byte address for prog port)
    -- 0x0C IMEM_WDATA
    -- 0x10 DMEM_ADDR   (byte address for prog port)
    -- 0x14 DMEM_WDATA
    -- 0x18 IMEM_PC     (debug)
    -- 0x1C LAST_DMEM_ADDR
    -- 0x20 LAST_DMEM_WDATA
    -- 0x24 UART_INJECT_DATA   (write bit 7..0 to send one UART byte)
    -- 0x28 UART_INJECT_STATUS (bit 0 = busy, bit 1 = injected RX line)
    ----------------------------------------------------------------------------

    constant CLK_FREQ_HZ        : integer := 100_000_000;
    constant UART_BAUD          : integer := 115200;
    constant UART_DIV           : integer := CLK_FREQ_HZ / UART_BAUD;

    constant REG_CONTROL        : integer := 0;
    constant REG_STATUS         : integer := 1;
    constant REG_IMEM_ADDR      : integer := 2;
    constant REG_IMEM_WDATA     : integer := 3;
    constant REG_DMEM_ADDR      : integer := 4;
    constant REG_DMEM_WDATA     : integer := 5;
    constant REG_IMEM_PC        : integer := 6;
    constant REG_LAST_DMEM_ADDR : integer := 7;
    constant REG_LAST_DMEM_DATA : integer := 8;
    constant REG_UART_INJ_DATA  : integer := 9;
    constant REG_UART_INJ_STAT  : integer := 10;

    signal clk   : STD_LOGIC;
    signal reset : STD_LOGIC;

    signal axi_awready_int : STD_LOGIC := '0';
    signal axi_wready_int  : STD_LOGIC := '0';
    signal axi_bvalid_int  : STD_LOGIC := '0';
    signal axi_arready_int : STD_LOGIC := '0';
    signal axi_rvalid_int  : STD_LOGIC := '0';
    signal axi_rdata_int   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal awaddr_int          : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal araddr_int          : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wdata_int           : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal write_addr_latched  : STD_LOGIC := '0';
    signal write_data_latched  : STD_LOGIC := '0';
    signal read_addr_latched   : STD_LOGIC := '0';

    signal cpu_enable_reg      : STD_LOGIC := '0';
    signal prog_mode_reg       : STD_LOGIC := '0';

    signal imem_addr_reg       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal imem_wdata_reg      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_addr_reg       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_wdata_reg      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal soft_reset_pulse    : STD_LOGIC := '0';
    signal imem_we_pulse       : STD_LOGIC := '0';
    signal dmem_we_pulse       : STD_LOGIC := '0';
    signal clear_status_pulse  : STD_LOGIC := '0';

    signal uart_inject_start   : STD_LOGIC := '0';
    signal uart_inject_data    : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal uart_inject_busy    : STD_LOGIC := '0';
    signal uart_inject_rx      : STD_LOGIC := '1';
    signal uart_shift          : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal uart_bit_index      : integer range 0 to 9 := 0;
    signal uart_div_count      : integer range 0 to UART_DIV-1 := 0;

    signal boot_done_dbg       : STD_LOGIC;
    signal boot_error_dbg      : STD_LOGIC;
    signal imem_pc_dbg         : STD_LOGIC_VECTOR(31 downto 0);
    signal dmem_we_dbg         : STD_LOGIC;
    signal dmem_addr_dbg       : STD_LOGIC_VECTOR(31 downto 0);
    signal dmem_wdata_dbg      : STD_LOGIC_VECTOR(31 downto 0);
    signal pass_latched        : STD_LOGIC := '0';
    signal fail_latched        : STD_LOGIC := '0';
    signal last_dmem_we_reg    : STD_LOGIC := '0';
    signal last_dmem_addr_reg  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal last_dmem_data_reg  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal core_reset          : STD_LOGIC;

begin

    clk   <= S_AXI_ACLK;
    reset <= not S_AXI_ARESETN;

    core_reset <= reset or soft_reset_pulse;
    ----------------------------------------------------------------------------
    -- AXI-driven UART injector
    --
    -- Vitis writes one byte to UART_INJECT_DATA. This block turns that byte into
    -- a real serial UART frame that feeds the SoC's uart_rx_i path.
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                uart_inject_busy <= '0';
                uart_inject_rx   <= '1';
                uart_shift       <= (others => '0');
                uart_bit_index   <= 0;
                uart_div_count   <= 0;
            elsif uart_inject_busy = '0' then
                uart_inject_rx <= '1';
                uart_div_count <= 0;
                uart_bit_index <= 0;

                if uart_inject_start = '1' then
                    uart_inject_busy <= '1';
                    uart_shift       <= uart_inject_data;
                    uart_inject_rx   <= '0';
                    uart_bit_index   <= 0;
                    uart_div_count   <= 0;
                end if;
            else
                if uart_div_count = UART_DIV-1 then
                    uart_div_count <= 0;

                    if uart_bit_index < 8 then
                        uart_inject_rx <= uart_shift(uart_bit_index);
                        uart_bit_index <= uart_bit_index + 1;
                    elsif uart_bit_index = 8 then
                        uart_inject_rx <= '1';
                        uart_bit_index <= 9;
                    else
                        uart_inject_busy <= '0';
                        uart_inject_rx   <= '1';
                        uart_bit_index   <= 0;
                    end if;
                else
                    uart_div_count <= uart_div_count + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- AXI Write Channel
    ----------------------------------------------------------------------------
    process(clk)
        variable reg_index : integer;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                axi_awready_int    <= '0';
                axi_wready_int     <= '0';
                axi_bvalid_int     <= '0';
                write_addr_latched <= '0';
                write_data_latched <= '0';
                wdata_int          <= (others => '0');

                cpu_enable_reg     <= '0';
                prog_mode_reg      <= '0';
                imem_addr_reg      <= (others => '0');
                imem_wdata_reg     <= (others => '0');
                dmem_addr_reg      <= (others => '0');
                dmem_wdata_reg     <= (others => '0');

                soft_reset_pulse   <= '0';
                imem_we_pulse      <= '0';
                dmem_we_pulse      <= '0';
                clear_status_pulse <= '0';
                uart_inject_start  <= '0';
            else
                soft_reset_pulse   <= '0';
                imem_we_pulse      <= '0';
                dmem_we_pulse      <= '0';
                clear_status_pulse <= '0';
                uart_inject_start  <= '0';

                if (S_AXI_AWVALID = '1') and (axi_awready_int = '0') then
                    axi_awready_int    <= '1';
                    awaddr_int         <= S_AXI_AWADDR;
                    write_addr_latched <= '1';
                end if;

                if (S_AXI_WVALID = '1') and (axi_wready_int = '0') then
                    axi_wready_int     <= '1';
                    wdata_int          <= S_AXI_WDATA;
                    write_data_latched <= '1';
                end if;

                if (write_addr_latched = '1') and (write_data_latched = '1') then
                    reg_index := to_integer(unsigned(awaddr_int(7 downto 2)));

                    case reg_index is
                        when REG_CONTROL =>
                            cpu_enable_reg <= wdata_int(0);
                            prog_mode_reg  <= wdata_int(5);

                            if wdata_int(1) = '1' then
                                soft_reset_pulse <= '1';
                            end if;

                            if wdata_int(2) = '1' then
                                imem_we_pulse <= '1';
                            end if;

                            if wdata_int(3) = '1' then
                                dmem_we_pulse <= '1';
                            end if;

                            if wdata_int(4) = '1' then
                                clear_status_pulse <= '1';
                            end if;

                        when REG_IMEM_ADDR =>
                            imem_addr_reg <= wdata_int;

                        when REG_IMEM_WDATA =>
                            imem_wdata_reg <= wdata_int;

                        when REG_DMEM_ADDR =>
                            dmem_addr_reg <= wdata_int;

                        when REG_DMEM_WDATA =>
                            dmem_wdata_reg <= wdata_int;

                        when REG_UART_INJ_DATA =>
                            if uart_inject_busy = '0' then
                                uart_inject_data  <= wdata_int(7 downto 0);
                                uart_inject_start <= '1';
                            end if;

                        when others =>
                            null;
                    end case;

                    axi_awready_int    <= '0';
                    axi_wready_int     <= '0';
                    axi_bvalid_int     <= '1';
                    write_addr_latched <= '0';
                    write_data_latched <= '0';
                end if;

                if (axi_bvalid_int = '1') and (S_AXI_BREADY = '1') then
                    axi_bvalid_int <= '0';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- AXI Read Address Channel
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                axi_arready_int   <= '0';
                araddr_int        <= (others => '0');
                read_addr_latched <= '0';
            elsif (S_AXI_ARVALID = '1') and (axi_arready_int = '0') then
                axi_arready_int   <= '1';
                araddr_int        <= S_AXI_ARADDR;
                read_addr_latched <= '1';
            else
                axi_arready_int   <= '0';
                read_addr_latched <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- AXI Read Data Channel
    ----------------------------------------------------------------------------
    process(clk)
        variable reg_index  : integer;
        variable status_reg : STD_LOGIC_VECTOR(31 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                axi_rvalid_int <= '0';
                axi_rdata_int  <= (others => '0');
            elsif read_addr_latched = '1' then
                axi_rvalid_int <= '1';
                reg_index      := to_integer(unsigned(araddr_int(7 downto 2)));

                status_reg := (others => '0');
                status_reg(0) := cpu_enable_reg;
                status_reg(1) := boot_done_dbg;
                status_reg(2) := last_dmem_we_reg;
                status_reg(3) := pass_latched;
                status_reg(4) := fail_latched;
                status_reg(5) := prog_mode_reg;
                status_reg(6) := boot_error_dbg;
                status_reg(7) := '0';
                status_reg(8) := uart_inject_busy;

                case reg_index is
                    when REG_CONTROL =>
                        axi_rdata_int <= (31 downto 7 => '0') &
                                         '0' &
                                         prog_mode_reg &
                                         '0' & '0' & '0' & '0' &
                                         cpu_enable_reg;

                    when REG_STATUS =>
                        axi_rdata_int <= status_reg;

                    when REG_IMEM_ADDR =>
                        axi_rdata_int <= imem_addr_reg;

                    when REG_IMEM_WDATA =>
                        axi_rdata_int <= imem_wdata_reg;

                    when REG_DMEM_ADDR =>
                        axi_rdata_int <= dmem_addr_reg;

                    when REG_DMEM_WDATA =>
                        axi_rdata_int <= dmem_wdata_reg;

                    when REG_IMEM_PC =>
                        axi_rdata_int <= imem_pc_dbg;

                    when REG_LAST_DMEM_ADDR =>
                        axi_rdata_int <= last_dmem_addr_reg;

                    when REG_LAST_DMEM_DATA =>
                        axi_rdata_int <= last_dmem_data_reg;

                    when REG_UART_INJ_DATA =>
                        axi_rdata_int <= (31 downto 8 => '0') & uart_inject_data;

                    when REG_UART_INJ_STAT =>
                        axi_rdata_int <= (31 downto 2 => '0') &
                                         uart_inject_rx &
                                         uart_inject_busy;

                    when others =>
                        axi_rdata_int <= (others => '0');
                end case;

            elsif (axi_rvalid_int = '1') and (S_AXI_RREADY = '1') then
                axi_rvalid_int <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Status / debug latching
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pass_latched       <= '0';
                fail_latched       <= '0';
                last_dmem_we_reg   <= '0';
                last_dmem_addr_reg <= (others => '0');
                last_dmem_data_reg <= (others => '0');
            else
                last_dmem_we_reg <= '0';

                if clear_status_pulse = '1' then
                    pass_latched <= '0';
                    fail_latched <= '0';
                end if;

                if dmem_we_dbg = '1' then
                    last_dmem_we_reg   <= '1';
                    last_dmem_addr_reg <= dmem_addr_dbg;
                    last_dmem_data_reg <= dmem_wdata_dbg;

                    if (dmem_addr_dbg = x"00001000") or (dmem_addr_dbg = x"80001000") then
                        if dmem_wdata_dbg = x"00000001" then
                            pass_latched <= '1';
                        elsif dmem_wdata_dbg /= x"00000000" then
                            fail_latched <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- AXI Outputs
    ----------------------------------------------------------------------------
    S_AXI_AWREADY <= axi_awready_int;
    S_AXI_WREADY  <= axi_wready_int;
    S_AXI_BVALID  <= axi_bvalid_int;
    S_AXI_BRESP   <= "00";

    S_AXI_ARREADY <= axi_arready_int;
    S_AXI_RVALID  <= axi_rvalid_int;
    S_AXI_RRESP   <= "00";
    S_AXI_RDATA   <= axi_rdata_int;

    ----------------------------------------------------------------------------
    -- Wrapped SoC
    ----------------------------------------------------------------------------
    u_soc : entity work.riscv_soc_boot
      generic map(
        CLK_FREQ_HZ => CLK_FREQ_HZ,
        BAUD        => UART_BAUD,
        IMEM_WORDS  => 4096
      )
      port map(
        clk       => clk,
        reset     => core_reset,
        uart_rx_i => uart_inject_rx,
        uart_tx_o => uart_tx_o,
        led0_o    => led0_o,

        boot_done_o  => boot_done_dbg,
        boot_error_o => boot_error_dbg,
        prog_we_o    => open,
        prog_addr_o  => open,
        prog_wdata_o => open,
        imem_pc_o    => imem_pc_dbg,
        dmem_we_o    => dmem_we_dbg,
        dmem_addr_o  => dmem_addr_dbg,
        dmem_wdata_o => dmem_wdata_dbg,

        ext_prog_mode_i   => prog_mode_reg,
        ext_cpu_enable_i  => cpu_enable_reg,
        ext_imem_we_i     => imem_we_pulse,
        ext_imem_addr_i   => imem_addr_reg,
        ext_imem_wdata_i  => imem_wdata_reg,
        ext_dmem_we_i     => dmem_we_pulse,
        ext_dmem_addr_i   => dmem_addr_reg,
        ext_dmem_wdata_i  => dmem_wdata_reg
      );

end Behavioral;
