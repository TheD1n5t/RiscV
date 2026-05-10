library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem is
  generic(
    G_FAULT_INJECT : boolean := false
  );
  port(
    clk              : in  std_logic;
    we               : in  std_logic;
    addr             : in  std_logic_vector(31 downto 0);
    data_in          : in  std_logic_vector(31 downto 0);
    data_out         : out std_logic_vector(31 downto 0);
    ecc_single_error : out std_logic;
    ecc_double_error : out std_logic;
    fi_dmem_mask_i   : in  std_logic_vector(38 downto 0);
    fi_dmem_addr_i   : in  std_logic_vector(9 downto 0);
    fi_dmem_strobe_i : in  std_logic;

    -- Bootloader programming path
    prog_we    : in  std_logic := '0';
    prog_addr  : in  std_logic_vector(31 downto 0) := (others => '0');
    prog_wdata : in  std_logic_vector(31 downto 0) := (others => '0')
  );
end dmem;

architecture syn of dmem is

  type ram_type is array (0 to 1023) of std_logic_vector(38 downto 0);
  signal ram : ram_type := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal rd_word_reg      : std_logic_vector(38 downto 0) := (others => '0');
  signal corrected_data_s : std_logic_vector(31 downto 0);
  signal single_err_s     : std_logic;
  signal double_err_s     : std_logic;

  -- Single effective write port after muxing
  signal wr_en_mux   : std_logic;
  signal wr_addr_mux : std_logic_vector(31 downto 0);
  signal wr_data_mux : std_logic_vector(31 downto 0);

  function get_codeword_from_data_and_parity(
    d  : std_logic_vector(31 downto 0);
    p  : std_logic_vector(5 downto 0);
    gp : std_logic
  ) return std_logic_vector is
    variable cw : std_logic_vector(38 downto 0) := (others => '0');
    variable di : integer := 0;
  begin
    for pos in 1 to 38 loop
      case pos is
        when 1  => cw(pos-1) := p(0);
        when 2  => cw(pos-1) := p(1);
        when 4  => cw(pos-1) := p(2);
        when 8  => cw(pos-1) := p(3);
        when 16 => cw(pos-1) := p(4);
        when 32 => cw(pos-1) := p(5);
        when others =>
          cw(pos-1) := d(di);
          di := di + 1;
      end case;
    end loop;
    cw(38) := gp;
    return cw;
  end function;

  function extract_data_from_codeword(
    cw : std_logic_vector(38 downto 0)
  ) return std_logic_vector is
    variable d  : std_logic_vector(31 downto 0) := (others => '0');
    variable di : integer := 0;
  begin
    for pos in 1 to 38 loop
      case pos is
        when 1 | 2 | 4 | 8 | 16 | 32 =>
          null;
        when others =>
          d(di) := cw(pos-1);
          di := di + 1;
      end case;
    end loop;
    return d;
  end function;

  function calc_hamming_parity(
    d : std_logic_vector(31 downto 0)
  ) return std_logic_vector is
    variable p       : std_logic_vector(5 downto 0) := (others => '0');
    variable cw      : std_logic_vector(37 downto 0) := (others => '0');
    variable di      : integer := 0;
    variable bit_xor : std_logic;
  begin
    for pos in 1 to 38 loop
      case pos is
        when 1 | 2 | 4 | 8 | 16 | 32 =>
          cw(pos-1) := '0';
        when others =>
          cw(pos-1) := d(di);
          di := di + 1;
      end case;
    end loop;

    for k in 0 to 5 loop
      bit_xor := '0';
      for pos in 1 to 38 loop
        if ((pos / (2**k)) mod 2) = 1 then
          if pos /= (2**k) then
            bit_xor := bit_xor xor cw(pos-1);
          end if;
        end if;
      end loop;
      p(k) := bit_xor;
    end loop;

    return p;
  end function;

  function calc_global_parity(
    d : std_logic_vector(31 downto 0);
    p : std_logic_vector(5 downto 0)
  ) return std_logic is
    variable gp : std_logic := '0';
    variable cw : std_logic_vector(37 downto 0);
  begin
    cw := get_codeword_from_data_and_parity(d, p, '0')(37 downto 0);
    for i in 0 to 37 loop
      gp := gp xor cw(i);
    end loop;
    return gp;
  end function;

  function encode_ecc(
    d : std_logic_vector(31 downto 0)
  ) return std_logic_vector is
    variable p  : std_logic_vector(5 downto 0);
    variable gp : std_logic;
    variable e  : std_logic_vector(6 downto 0);
  begin
    p  := calc_hamming_parity(d);
    gp := calc_global_parity(d, p);
    e(5 downto 0) := p;
    e(6)          := gp;
    return e;
  end function;

begin

  --------------------------------------------------------------------
  -- Write mux: bootloader has priority over normal CPU write
  --------------------------------------------------------------------
  wr_en_mux   <= prog_we or we;
  wr_addr_mux <= prog_addr  when prog_we = '1' else addr;
  wr_data_mux <= prog_wdata when prog_we = '1' else data_in;

  --------------------------------------------------------------------
  -- Single-port RAM process:
  -- 1) registered read path via CPU read address
  -- 2) exactly one effective write port after muxing
  --------------------------------------------------------------------
  process(clk)
    variable rd_addr_int : integer range 0 to 1023;
    variable wr_addr_int : integer range 0 to 1023;
    variable fia_int     : integer range 0 to 1023;
    variable ecc_v       : std_logic_vector(6 downto 0);
  begin
    if rising_edge(clk) then
      rd_addr_int := to_integer(unsigned(addr(11 downto 2)));
      wr_addr_int := to_integer(unsigned(wr_addr_mux(11 downto 2)));

      -- synchronous CPU read
      rd_word_reg <= ram(rd_addr_int);

      -- single effective write path
      if wr_en_mux = '1' then
        ecc_v := encode_ecc(wr_data_mux);
        ram(wr_addr_int) <= ecc_v & wr_data_mux;

      elsif G_FAULT_INJECT and fi_dmem_strobe_i = '1' then
        fia_int := to_integer(unsigned(fi_dmem_addr_i));
        ram(fia_int) <= ram(fia_int) xor fi_dmem_mask_i;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- ECC decode/correct from registered read word
  --------------------------------------------------------------------
  process(rd_word_reg)
    variable stored_data   : std_logic_vector(31 downto 0);
    variable stored_ecc    : std_logic_vector(6 downto 0);
    variable p_calc        : std_logic_vector(5 downto 0);
    variable gp_calc       : std_logic;
    variable syndrome      : unsigned(5 downto 0);
    variable overall_error : std_logic;
    variable cw            : std_logic_vector(38 downto 0);
    variable d_corr        : std_logic_vector(31 downto 0);
    variable se            : std_logic;
    variable de            : std_logic;
  begin
    stored_data := rd_word_reg(31 downto 0);
    stored_ecc  := rd_word_reg(38 downto 32);

    p_calc  := calc_hamming_parity(stored_data);
    gp_calc := calc_global_parity(stored_data, stored_ecc(5 downto 0));

    syndrome      := unsigned(p_calc xor stored_ecc(5 downto 0));
    overall_error := gp_calc xor stored_ecc(6);

    cw := get_codeword_from_data_and_parity(
            stored_data,
            stored_ecc(5 downto 0),
            stored_ecc(6)
          );

    d_corr := stored_data;
    se     := '0';
    de     := '0';

    if syndrome /= 0 then
      if overall_error = '1' then
        se := '1';
        if to_integer(syndrome) >= 1 and to_integer(syndrome) <= 38 then
          cw(to_integer(syndrome)-1) := not cw(to_integer(syndrome)-1);
        end if;
        d_corr := extract_data_from_codeword(cw);
      else
        de := '1';
      end if;
    else
      if overall_error = '1' then
        se := '1';
      end if;
    end if;

    corrected_data_s <= d_corr;
    single_err_s     <= se;
    double_err_s     <= de;
  end process;

  data_out         <= corrected_data_s;
  ecc_single_error <= single_err_s;
  ecc_double_error <= double_err_s;

end syn;