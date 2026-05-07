library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fake_spi_flash is
  port(
    sck_i   : in  std_logic;
    cs_n_i  : in  std_logic;
    mosi_i  : in  std_logic;
    miso_o  : out std_logic
  );
end entity;

architecture rtl of fake_spi_flash is

  type rom_t is array(0 to 255) of std_logic_vector(7 downto 0);

  constant rom : rom_t := (
    -- Header: magic 55 AA, IMEM length = 12 bytes, DMEM length = 0 bytes.
    0  => x"55",
    1  => x"AA",
    2  => x"0C",
    3  => x"00",
    4  => x"00",
    5  => x"00",
    6  => x"00",
    7  => x"00",
    8  => x"00",
    9  => x"00",

    -- addi x1, x0, 123
    10 => x"93",
    11 => x"00",
    12 => x"B0",
    13 => x"07",

    -- sw x1, 0(x0)
    14 => x"23",
    15 => x"20",
    16 => x"10",
    17 => x"00",

    -- jal x0, 0
    18 => x"6F",
    19 => x"00",
    20 => x"00",
    21 => x"00",

    others => x"00"
  );

  signal cmd_shift  : std_logic_vector(7 downto 0) := (others => '0');
  signal addr_shift : std_logic_vector(23 downto 0) := (others => '0');
  signal bit_count  : unsigned(7 downto 0) := (others => '0');
  signal read_index : unsigned(7 downto 0) := (others => '0');
  signal read_bit   : integer range 0 to 7 := 7;
  signal miso_r     : std_logic := '0';

begin

  miso_o <= miso_r;

  process(sck_i, cs_n_i)
  begin
    if cs_n_i = '1' then
      cmd_shift  <= (others => '0');
      addr_shift <= (others => '0');
      bit_count  <= (others => '0');
      read_index <= (others => '0');
      read_bit   <= 7;
      miso_r     <= '0';
    elsif rising_edge(sck_i) then
      if bit_count < 8 then
        cmd_shift <= cmd_shift(6 downto 0) & mosi_i;
      elsif bit_count < 32 then
        addr_shift <= addr_shift(22 downto 0) & mosi_i;
      end if;
    elsif falling_edge(sck_i) then
      if bit_count >= 31 then
        miso_r <= rom(to_integer(read_index))(read_bit);

        if read_bit = 0 then
          read_bit <= 7;
          read_index <= read_index + 1;
        else
          read_bit <= read_bit - 1;
        end if;
      end if;

      bit_count <= bit_count + 1;
    end if;
  end process;

end architecture;
