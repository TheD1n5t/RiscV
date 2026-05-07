library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
  generic(
    G_FAULT_INJECT : boolean := false;
    G_SELF_HEAL    : boolean := false
  );
  port (
    clk                 : in  std_logic;
    rst                 : in  std_logic;
    we                  : in  std_logic;
    reg_in_data         : in  std_logic_vector(31 downto 0);
    reg_read_addr1      : in  std_logic_vector(4 downto 0);
    reg_read_addr2      : in  std_logic_vector(4 downto 0);
    reg_write_addr      : in  std_logic_vector(4 downto 0);
    reg_out_data1       : out std_logic_vector(31 downto 0);
    reg_out_data2       : out std_logic_vector(31 downto 0);
    regfile_tmr_error_o : out std_logic;

    fi_rf_mask_i        : in  std_logic_vector(31 downto 0) := (others => '0');
    fi_rf_addr_i        : in  std_logic_vector(4 downto 0)  := (others => '0');
    fi_rf_target_i      : in  std_logic_vector(1 downto 0)  := "00";
    fi_rf_strobe_i      : in  std_logic := '0'
  );
end regfile;

architecture rtl of regfile is

  type mem_t is array(0 to 31) of std_logic_vector(31 downto 0);

  signal regfile_a : mem_t := (others => (others => '0'));
  signal regfile_b : mem_t := (others => (others => '0'));
  signal regfile_c : mem_t := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of regfile_a : signal is "distributed";
  attribute ram_style of regfile_b : signal is "distributed";
  attribute ram_style of regfile_c : signal is "distributed";

  signal read_a1      : std_logic_vector(31 downto 0);
  signal read_b1      : std_logic_vector(31 downto 0);
  signal read_c1      : std_logic_vector(31 downto 0);
  signal read_a2      : std_logic_vector(31 downto 0);
  signal read_b2      : std_logic_vector(31 downto 0);
  signal read_c2      : std_logic_vector(31 downto 0);

  signal voted_r1     : std_logic_vector(31 downto 0);
  signal voted_r2     : std_logic_vector(31 downto 0);

  signal mismatch_r1  : std_logic;
  signal mismatch_r2  : std_logic;

  function majority3_vec(
    a : std_logic_vector(31 downto 0);
    b : std_logic_vector(31 downto 0);
    c : std_logic_vector(31 downto 0)
  ) return std_logic_vector is
    variable r : std_logic_vector(31 downto 0);
  begin
    for i in 0 to 31 loop
      r(i) := (a(i) and b(i)) or (a(i) and c(i)) or (b(i) and c(i));
    end loop;
    return r;
  end function;

begin

  --------------------------------------------------------------------
  -- Async reads from the 3 banks
  --------------------------------------------------------------------
  read_a1 <= regfile_a(to_integer(unsigned(reg_read_addr1)));
  read_b1 <= regfile_b(to_integer(unsigned(reg_read_addr1)));
  read_c1 <= regfile_c(to_integer(unsigned(reg_read_addr1)));

  read_a2 <= regfile_a(to_integer(unsigned(reg_read_addr2)));
  read_b2 <= regfile_b(to_integer(unsigned(reg_read_addr2)));
  read_c2 <= regfile_c(to_integer(unsigned(reg_read_addr2)));

  voted_r1 <= majority3_vec(read_a1, read_b1, read_c1);
  voted_r2 <= majority3_vec(read_a2, read_b2, read_c2);

  mismatch_r1 <= '1' when (read_a1 /= read_b1) or (read_a1 /= read_c1) or (read_b1 /= read_c1) else '0';
  mismatch_r2 <= '1' when (read_a2 /= read_b2) or (read_a2 /= read_c2) or (read_b2 /= read_c2) else '0';

  regfile_tmr_error_o <= mismatch_r1 or mismatch_r2;

  --------------------------------------------------------------------
  -- Write / FI / Self-heal
  --------------------------------------------------------------------
  process(clk)
    variable waddr_int   : integer range 0 to 31;
    variable raddr1_int  : integer range 0 to 31;
    variable raddr2_int  : integer range 0 to 31;
    variable fi_addr_int : integer range 0 to 31;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        regfile_a <= (others => (others => '0'));
        regfile_b <= (others => (others => '0'));
        regfile_c <= (others => (others => '0'));

      else
        waddr_int   := to_integer(unsigned(reg_write_addr));
        raddr1_int  := to_integer(unsigned(reg_read_addr1));
        raddr2_int  := to_integer(unsigned(reg_read_addr2));
        fi_addr_int := to_integer(unsigned(fi_rf_addr_i));

        if we = '1' and reg_write_addr /= "00000" then
          regfile_a(waddr_int) <= reg_in_data;
          regfile_b(waddr_int) <= reg_in_data;
          regfile_c(waddr_int) <= reg_in_data;

        elsif G_FAULT_INJECT and fi_rf_strobe_i = '1' and fi_rf_addr_i /= "00000" then
          case fi_rf_target_i is
            when "00" =>
              regfile_a(fi_addr_int) <= regfile_a(fi_addr_int) xor fi_rf_mask_i;
            when "01" =>
              regfile_b(fi_addr_int) <= regfile_b(fi_addr_int) xor fi_rf_mask_i;
            when "10" =>
              regfile_c(fi_addr_int) <= regfile_c(fi_addr_int) xor fi_rf_mask_i;
            when others =>
              null;
          end case;

        elsif G_SELF_HEAL and reg_read_addr1 /= "00000" and mismatch_r1 = '1' then
          regfile_a(raddr1_int) <= voted_r1;
          regfile_b(raddr1_int) <= voted_r1;
          regfile_c(raddr1_int) <= voted_r1;

        elsif G_SELF_HEAL and reg_read_addr2 /= "00000" and mismatch_r2 = '1' then
          regfile_a(raddr2_int) <= voted_r2;
          regfile_b(raddr2_int) <= voted_r2;
          regfile_c(raddr2_int) <= voted_r2;
        end if;

        regfile_a(0) <= (others => '0');
        regfile_b(0) <= (others => '0');
        regfile_c(0) <= (others => '0');
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Read outputs with write-through
  --------------------------------------------------------------------
  reg_out_data1 <= reg_in_data
    when (we = '1' and reg_write_addr /= "00000" and reg_write_addr = reg_read_addr1)
    else voted_r1;

  reg_out_data2 <= reg_in_data
    when (we = '1' and reg_write_addr /= "00000" and reg_write_addr = reg_read_addr2)
    else voted_r2;

end rtl;