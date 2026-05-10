library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
generic(
    CLK_FREQ_HZ : integer := 50_000_000;
    BAUD        : integer := 115200
);
port(
    clk     : in  std_logic;
    reset   : in  std_logic;
    rx      : in  std_logic;

    rx_data : out std_logic_vector(7 downto 0);
    rx_valid: out std_logic
);
end uart_rx;

architecture rtl of uart_rx is
    constant DIV : integer := CLK_FREQ_HZ / BAUD;  -- clocks per bit
    type state_t is (IDLE, START, DATA_BITS, STOP);
    signal st : state_t := IDLE;

    signal cnt    : integer range 0 to DIV-1 := 0;
    signal bitidx : integer range 0 to 7 := 0;

    signal shift    : std_logic_vector(7 downto 0) := (others=>'0');
    signal rx_data_r: std_logic_vector(7 downto 0) := (others=>'0');

    -- 2FF sync
    signal rx_sync : std_logic_vector(1 downto 0) := (others=>'1');
begin
    rx_data <= rx_data_r;

    -- synchronize RX
    process(clk)
    begin
        if rising_edge(clk) then
            rx_sync <= rx_sync(0) & rx;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then
                st        <= IDLE;
                cnt       <= 0;
                bitidx    <= 0;
                shift     <= (others=>'0');
                rx_data_r <= (others=>'0');
                rx_valid  <= '0';
            else
                rx_valid <= '0';

                case st is
                    when IDLE =>
                        cnt    <= 0;
                        bitidx <= 0;
                        if rx_sync(1)='0' then
                            -- start bit seen
                            st <= START;
                        end if;

                    when START =>
                        -- sample in the middle of start bit
                        if cnt = (DIV/2) then
                            if rx_sync(1)='0' then
                                cnt <= 0;
                                st  <= DATA_BITS;
                            else
                                st  <= IDLE; -- false start
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when DATA_BITS =>
                        if cnt = DIV-1 then
                            cnt <= 0;
                            shift(bitidx) <= rx_sync(1);

                            if bitidx = 7 then
                                bitidx <= 0;
                                st     <= STOP;
                            else
                                bitidx <= bitidx + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when STOP =>
                        if cnt = DIV-1 then
                            cnt <= 0;
                            rx_data_r <= shift;
                            rx_valid  <= '1';
                            st        <= IDLE;
                        else
                            cnt <= cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;
end rtl;
