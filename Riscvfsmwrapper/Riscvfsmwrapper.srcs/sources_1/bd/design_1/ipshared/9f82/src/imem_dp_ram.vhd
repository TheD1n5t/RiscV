library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity imem_dp_ram is
  generic(
    WORDS          : integer := 4096;
    G_FAULT_INJECT : boolean := false
  );
  port(
    clk : in std_logic;

    -- Fetch port
    pc        : in  std_logic_vector(31 downto 0);
    instr_out : out std_logic_vector(31 downto 0);

    -- Program port (word address)
    prog_we    : in  std_logic;
    prog_addr  : in  std_logic_vector(31 downto 0);
    prog_wdata : in  std_logic_vector(31 downto 0);

    -- Fault injection for IMEM
    fi_imem_mask_i   : in std_logic_vector(38 downto 0) := (others => '0');
    fi_imem_addr_i   : in std_logic_vector(11 downto 0) := (others => '0');
    fi_imem_strobe_i : in std_logic := '0'
  );
end imem_dp_ram;

architecture rtl of imem_dp_ram is

  --------------------------------------------------------------------
  -- 39-bit ECC codeword RAM
  --------------------------------------------------------------------
  type ram_t is array (0 to WORDS-1) of std_logic_vector(38 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal fetch_addr  : unsigned(29 downto 0);
  signal prog_addr_u : unsigned(31 downto 0);
  signal fi_addr_u   : unsigned(11 downto 0);

  signal rd_word_reg : std_logic_vector(38 downto 0) := (others => '0');
  signal instr_reg   : std_logic_vector(31 downto 0) := x"00000013";

  --------------------------------------------------------------------
  -- Build full codeword from data + parity bits
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Extract 32-bit data from codeword
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Calculate Hamming parity bits
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Calculate global parity
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Encode ECC bits [6:0]
  --------------------------------------------------------------------
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

  fetch_addr  <= unsigned(pc(31 downto 2));
  prog_addr_u <= unsigned(prog_addr);
  fi_addr_u   <= unsigned(fi_imem_addr_i);

  --------------------------------------------------------------------
  -- RAM process
  --------------------------------------------------------------------
  process(clk)
    variable fa_int  : integer;
    variable pa_int  : integer;
    variable fia_int : integer;
    variable ecc_v   : std_logic_vector(6 downto 0);
  begin
    if rising_edge(clk) then

      -- synchronous fetch read
      fa_int := to_integer(fetch_addr);
      if fa_int >= 0 and fa_int < WORDS then
        rd_word_reg <= ram(fa_int);
      else
        rd_word_reg <= encode_ecc(x"00000013") & x"00000013";
      end if;

      -- boot/program write
      if prog_we = '1' then
        pa_int := to_integer(prog_addr_u);
        if pa_int >= 0 and pa_int < WORDS then
          ecc_v := encode_ecc(prog_wdata);
          ram(pa_int) <= ecc_v & prog_wdata;
        end if;

      -- fault injection into stored codeword
     elsif G_FAULT_INJECT and fi_imem_strobe_i = '1' then
        fia_int := to_integer(fi_addr_u);
        if fia_int >= 0 and fia_int < WORDS then
          ram(fia_int) <= ram(fia_int) xor fi_imem_mask_i;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- ECC decode / correction
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

    if syndrome /= 0 then
      if overall_error = '1' then
        if to_integer(syndrome) >= 1 and to_integer(syndrome) <= 38 then
          cw(to_integer(syndrome)-1) := not cw(to_integer(syndrome)-1);
        end if;
        d_corr := extract_data_from_codeword(cw);
      else
        d_corr := stored_data;
      end if;
    else
      if overall_error = '1' then
        d_corr := stored_data;
      end if;
    end if;

    instr_reg <= d_corr;
  end process;

  instr_out <= instr_reg;

end rtl;