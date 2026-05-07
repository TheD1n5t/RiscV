library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem is
  port(
    clk       : in  std_logic;
    we        : in  std_logic;
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

  signal wr_en_mux   : std_logic;
  signal wr_addr_mux : std_logic_vector(31 downto 0);
  signal wr_data_mux : std_logic_vector(31 downto 0);

begin

  wr_en_mux   <= prog_we or we;
  wr_addr_mux <= prog_addr  when prog_we = '1' else addr;
  wr_data_mux <= prog_wdata when prog_we = '1' else data_in;

  process(clk)
    variable rd_addr_int : integer range 0 to 1023;
    variable wr_addr_int : integer range 0 to 1023;
  begin
    if rising_edge(clk) then
      rd_addr_int := to_integer(unsigned(addr(11 downto 2)));
      wr_addr_int := to_integer(unsigned(wr_addr_mux(11 downto 2)));

      rd_data_reg <= ram(rd_addr_int);

      if wr_en_mux = '1' then
        ram(wr_addr_int) <= wr_data_mux;
      end if;
    end if;
  end process;

  data_out <= rd_data_reg;

end syn;
