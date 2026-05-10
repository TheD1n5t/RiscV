library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem is
  port(
    clk       : in  std_logic;
    we        : in  std_logic;
    be        : in  std_logic_vector(3 downto 0) := "1111";
    addr      : in  std_logic_vector(31 downto 0);
    data_in   : in  std_logic_vector(31 downto 0);
    data_out  : out std_logic_vector(31 downto 0);

    -- Bootloader programming path
    prog_we    : in  std_logic := '0';
    prog_addr  : in  std_logic_vector(31 downto 0) := (others => '0');
    prog_wdata : in  std_logic_vector(31 downto 0) := (others => '0')
  );
end dmem;

architecture syn of dmem is

  type ram_type is array (0 to 1023) of std_logic_vector(31 downto 0);
  signal ram : ram_type := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal rd_data_reg : std_logic_vector(31 downto 0) := (others => '0');

begin

  process(clk)
    variable rd_addr_int : integer range 0 to 1023;
    variable wr_addr_int : integer range 0 to 1023;
  begin
    if rising_edge(clk) then
      rd_addr_int := to_integer(unsigned(addr(11 downto 2)));
      rd_data_reg <= ram(rd_addr_int);

      if prog_we = '1' then
        wr_addr_int := to_integer(unsigned(prog_addr(11 downto 2)));
        ram(wr_addr_int) <= prog_wdata;
      elsif we = '1' then
        wr_addr_int := to_integer(unsigned(addr(11 downto 2)));

        if be(0) = '1' then
          ram(wr_addr_int)(7 downto 0) <= data_in(7 downto 0);
        end if;

        if be(1) = '1' then
          ram(wr_addr_int)(15 downto 8) <= data_in(15 downto 8);
        end if;

        if be(2) = '1' then
          ram(wr_addr_int)(23 downto 16) <= data_in(23 downto 16);
        end if;

        if be(3) = '1' then
          ram(wr_addr_int)(31 downto 24) <= data_in(31 downto 24);
        end if;
      end if;
    end if;
  end process;

  data_out <= rd_data_reg;

end syn;
