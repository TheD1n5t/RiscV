library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity imem_dp_ram is
  generic(
    WORDS : integer := 4096
  );
  port(
    clk : in std_logic;

    -- Fetch port
    pc        : in  std_logic_vector(31 downto 0);
    instr_out : out std_logic_vector(31 downto 0);

    -- Program port (byte address)
    prog_we    : in  std_logic;
    prog_addr  : in  std_logic_vector(31 downto 0);
    prog_wdata : in  std_logic_vector(31 downto 0)
  );
end imem_dp_ram;

architecture rtl of imem_dp_ram is

  type ram_t is array (0 to WORDS-1) of std_logic_vector(31 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal fetch_addr : unsigned(29 downto 0);
  signal instr_reg  : std_logic_vector(31 downto 0) := x"00000013";

begin

  fetch_addr <= unsigned(pc(31 downto 2));

  process(clk)
    variable fa_int : integer;
    variable pa_int : integer;
  begin
    if rising_edge(clk) then
      fa_int := to_integer(fetch_addr);
      if fa_int >= 0 and fa_int < WORDS then
        instr_reg <= ram(fa_int);
      else
        instr_reg <= x"00000013";
      end if;

      if prog_we = '1' then
        pa_int := to_integer(unsigned(prog_addr(31 downto 2)));
        if pa_int >= 0 and pa_int < WORDS then
          ram(pa_int) <= prog_wdata;
        end if;
      end if;
    end if;
  end process;

  instr_out <= instr_reg;

end rtl;
