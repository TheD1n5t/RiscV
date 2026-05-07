library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
generic(
  CLK_FREQ_HZ : integer := 50_000_000;
  BAUD        : integer := 115200
);
port(
  clk   : in  std_logic;
  reset : in  std_logic;

  start : in  std_logic;                 -- 1 Takt Puls
  data  : in  std_logic_vector(7 downto 0);

  tx    : out std_logic;                 -- UART TX line
  busy  : out std_logic                  -- 1 = sending
);
end entity;

architecture rtl of uart_tx is
  constant DIV : integer := CLK_FREQ_HZ / BAUD; -- ticks per bit (integer)
  signal div_cnt : integer range 0 to DIV-1 := 0;

  type st_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal st : st_t := IDLE;

  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_cnt : integer range 0 to 7 := 0;

  signal tx_r : std_logic := '1';
begin
  tx   <= tx_r;
  busy <= '0' when st = IDLE else '1';

  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then
        st      <= IDLE;
        div_cnt <= 0;
        shreg   <= (others=>'0');
        bit_cnt <= 0;
        tx_r    <= '1';
      else
        case st is
          when IDLE =>
            tx_r <= '1';
            div_cnt <= 0;
            if start='1' then
              shreg   <= data;
              bit_cnt <= 0;
              st      <= START_BIT;
            end if;

          when START_BIT =>
            tx_r <= '0';
            if div_cnt = DIV-1 then
              div_cnt <= 0;
              st <= DATA_BITS;
            else
              div_cnt <= div_cnt + 1;
            end if;

          when DATA_BITS =>
            tx_r <= shreg(0);
            if div_cnt = DIV-1 then
              div_cnt <= 0;
              shreg <= '0' & shreg(7 downto 1); -- shift right, LSB first
              if bit_cnt = 7 then
                st <= STOP_BIT;
              else
                bit_cnt <= bit_cnt + 1;
              end if;
            else
              div_cnt <= div_cnt + 1;
            end if;

          when STOP_BIT =>
            tx_r <= '1';
            if div_cnt = DIV-1 then
              div_cnt <= 0;
              st <= IDLE;
            else
              div_cnt <= div_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
