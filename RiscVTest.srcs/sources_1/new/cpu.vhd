library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_core_memless is
  generic(
    G_FAULT_INJECT : boolean := false;
    G_PC_TMR       : boolean := true;
    G_STATE_TMR    : boolean := true;
    G_RF_TMR       : boolean := true;
    G_RF_SELF_HEAL : boolean := true
  );
  port(
    clk   : in  std_logic;
    reset : in  std_logic;

    -- Instruction memory interface (synchronous read assumed)
    imem_pc    : out std_logic_vector(31 downto 0);
    imem_instr : in  std_logic_vector(31 downto 0);

    -- Data memory interface (synchronous read assumed)
    dmem_we    : out std_logic;
    dmem_addr  : out std_logic_vector(31 downto 0);
    dmem_wdata : out std_logic_vector(31 downto 0);
    dmem_rdata : in  std_logic_vector(31 downto 0);

    -- External machine timer interrupt
    irq_timer_i : in std_logic;

    -- Fault injection for PC TMR
    fi_pc_mask_i   : in std_logic_vector(31 downto 0) := (others => '0');
    fi_pc_target_i : in std_logic_vector(1 downto 0)  := "00"; -- 00=a, 01=b, 10=c
    fi_pc_strobe_i : in std_logic := '0';

    -- Fault injection for STATE TMR
    fi_state_mask_i   : in std_logic_vector(3 downto 0) := (others => '0');
    fi_state_target_i : in std_logic_vector(1 downto 0) := "00"; -- 00=a, 01=b, 10=c
    fi_state_strobe_i : in std_logic := '0';
    
    -- Fault injection for RF TMR
    fi_rf_mask_i   : in std_logic_vector(31 downto 0) := (others => '0');
    fi_rf_addr_i   : in std_logic_vector(4 downto 0)  := (others => '0');
    fi_rf_target_i : in std_logic_vector(1 downto 0)  := "00";
    fi_rf_strobe_i : in std_logic := '0';
    -- Watchdog reset pulse from CSR block
    watchdog_reset_o        : out std_logic;
    dmem_ecc_single_error_i : in std_logic := '0';
    dmem_ecc_double_error_i : in std_logic := '0';
    imem_ecc_single_error_i : in std_logic := '0';
    imem_ecc_double_error_i : in std_logic := '0';

    pc_tmr_error_o          : out std_logic := '0';
    state_tmr_error_o       : out std_logic := '0';
    regfile_tmr_error_o     : out std_logic := '0'
  );
end riscv_core_memless;

architecture rtl of riscv_core_memless is

  --------------------------------------------------------------------
  -- Types and constants
  --------------------------------------------------------------------
  type state_t is (
    ST_RESET,
    ST_FETCH,
    ST_FETCH_WAIT,
    ST_DECODE,
    ST_RF_WAIT,
    ST_EXEC_ALU,
    ST_EXEC_LOAD_ADDR,
    ST_EXEC_STORE_ADDR,
    ST_EXEC_BRANCH,
    ST_EXEC_JUMP,
    ST_EXEC_CSR,
    ST_MEM_READ,
    ST_MEM_WRITE,
    ST_TRAP,
    ST_MRET,
    ST_WB
  );

  constant NOP : std_logic_vector(31 downto 0) := x"00000013";

  --------------------------------------------------------------------
  -- Helper functions for STATE TMR FI
  --------------------------------------------------------------------
  function state_to_slv(s : state_t) return std_logic_vector is
  begin
    case s is
      when ST_RESET           => return "0000";
      when ST_FETCH           => return "0001";
      when ST_FETCH_WAIT      => return "0010";
      when ST_DECODE          => return "0011";
      when ST_RF_WAIT         => return "0100";
      when ST_EXEC_ALU        => return "0101";
      when ST_EXEC_LOAD_ADDR  => return "0110";
      when ST_EXEC_STORE_ADDR => return "0111";
      when ST_EXEC_BRANCH     => return "1000";
      when ST_EXEC_JUMP       => return "1001";
      when ST_EXEC_CSR        => return "1010";
      when ST_MEM_READ        => return "1011";
      when ST_MEM_WRITE       => return "1100";
      when ST_TRAP            => return "1101";
      when ST_MRET            => return "1110";
      when ST_WB              => return "1111";
    end case;
  end function;

  function slv_to_state(v : std_logic_vector(3 downto 0)) return state_t is
  begin
    case v is
      when "0000" => return ST_RESET;
      when "0001" => return ST_FETCH;
      when "0010" => return ST_FETCH_WAIT;
      when "0011" => return ST_DECODE;
      when "0100" => return ST_RF_WAIT;
      when "0101" => return ST_EXEC_ALU;
      when "0110" => return ST_EXEC_LOAD_ADDR;
      when "0111" => return ST_EXEC_STORE_ADDR;
      when "1000" => return ST_EXEC_BRANCH;
      when "1001" => return ST_EXEC_JUMP;
      when "1010" => return ST_EXEC_CSR;
      when "1011" => return ST_MEM_READ;
      when "1100" => return ST_MEM_WRITE;
      when "1101" => return ST_TRAP;
      when "1110" => return ST_MRET;
      when "1111" => return ST_WB;
      when others => return ST_RESET;
    end case;
  end function;

  --------------------------------------------------------------------
  -- TMR-protected core state
  --------------------------------------------------------------------
  signal state_a          : state_t := ST_RESET;
  signal state_b          : state_t := ST_RESET;
  signal state_c          : state_t := ST_RESET;
  signal state_v          : state_t := ST_RESET;

  signal state_tmr_error  : std_logic := '0';

  signal state_enc_a      : std_logic_vector(3 downto 0);
  signal state_enc_b      : std_logic_vector(3 downto 0);
  signal state_enc_c      : std_logic_vector(3 downto 0);

  signal state_v_slv      : std_logic_vector(3 downto 0) := "0000";

  signal pc_a             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_b             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_c             : std_logic_vector(31 downto 0) := (others => '0');

  signal pc_v             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_tmr_error     : std_logic := '0';

  signal instr_reg        : std_logic_vector(31 downto 0) := NOP;
  signal instr_pc         : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_plus4         : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Decoder outputs
  --------------------------------------------------------------------
  signal rs1              : std_logic_vector(4 downto 0);
  signal rs2              : std_logic_vector(4 downto 0);
  signal rd               : std_logic_vector(4 downto 0);
  signal imm              : std_logic_vector(31 downto 0);

  signal alu_op           : std_logic_vector(3 downto 0);
  signal alu_src          : std_logic;
  signal reg_write_dec    : std_logic;
  signal mem_write_dec    : std_logic;
  signal mem_read_dec     : std_logic;
  signal mem_to_reg_dec   : std_logic;
  signal branch_dec       : std_logic;
  signal branch_type      : std_logic_vector(2 downto 0);
  signal jump_dec         : std_logic;
  signal jalr_dec         : std_logic;
  signal is_auipc         : std_logic;

  signal load_size        : std_logic_vector(1 downto 0);
  signal load_sign        : std_logic;
  signal store_size       : std_logic_vector(1 downto 0);

  signal is_ecall         : std_logic;
  signal is_ebreak        : std_logic;
  signal is_mret          : std_logic;
  signal illegal_instr    : std_logic;

  signal csr_en           : std_logic;
  signal csr_we           : std_logic;
  signal csr_addr         : std_logic_vector(11 downto 0);
  signal csr_use_imm      : std_logic;
  signal csr_cmd          : std_logic_vector(1 downto 0);

  --------------------------------------------------------------------
  -- Register file interface
  --------------------------------------------------------------------
  signal reg_rs1          : std_logic_vector(31 downto 0);
  signal reg_rs2          : std_logic_vector(31 downto 0);

  signal rf_we            : std_logic := '0';
  signal rf_waddr         : std_logic_vector(4 downto 0) := (others => '0');
  signal rf_wdata         : std_logic_vector(31 downto 0) := (others => '0');

  signal regfile_tmr_error : std_logic := '0';

  --------------------------------------------------------------------
  -- Latched instruction context
  --------------------------------------------------------------------
  signal cur_rs1_addr     : std_logic_vector(4 downto 0) := (others => '0');
  signal cur_rs2_addr     : std_logic_vector(4 downto 0) := (others => '0');
  signal cur_rd_addr      : std_logic_vector(4 downto 0) := (others => '0');

  signal cur_rs1_val      : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_rs2_val      : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_imm          : std_logic_vector(31 downto 0) := (others => '0');

  signal cur_alu_op       : std_logic_vector(3 downto 0) := (others => '0');
  signal cur_alu_src      : std_logic := '0';
  signal cur_branch_ty    : std_logic_vector(2 downto 0) := (others => '0');

  signal cur_reg_write    : std_logic := '0';
  signal cur_mem_write    : std_logic := '0';
  signal cur_mem_read     : std_logic := '0';
  signal cur_mem_to_reg   : std_logic := '0';
  signal cur_jump         : std_logic := '0';
  signal cur_jalr         : std_logic := '0';
  signal cur_branch       : std_logic := '0';
  signal cur_is_auipc     : std_logic := '0';

  signal cur_load_size    : std_logic_vector(1 downto 0) := "10";
  signal cur_load_sign    : std_logic := '1';
  signal cur_store_size   : std_logic_vector(1 downto 0) := "10";

  signal cur_is_ecall     : std_logic := '0';
  signal cur_is_ebreak    : std_logic := '0';
  signal cur_is_mret      : std_logic := '0';
  signal cur_illegal      : std_logic := '0';

  signal cur_csr_en       : std_logic := '0';
  signal cur_csr_we       : std_logic := '0';
  signal cur_csr_addr     : std_logic_vector(11 downto 0) := (others => '0');
  signal cur_csr_use_imm  : std_logic := '0';
  signal cur_csr_cmd      : std_logic_vector(1 downto 0) := "11";

  --------------------------------------------------------------------
  -- Execute / writeback data
  --------------------------------------------------------------------
  signal alu_a            : std_logic_vector(31 downto 0);
  signal alu_b            : std_logic_vector(31 downto 0);
  signal alu_result       : std_logic_vector(31 downto 0);

  signal exec_result      : std_logic_vector(31 downto 0) := (others => '0');
  signal mem_addr_reg     : std_logic_vector(31 downto 0) := (others => '0');
  signal load_data_reg    : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_read_reg     : std_logic_vector(31 downto 0) := (others => '0');
  signal next_pc_reg      : std_logic_vector(31 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- Branch / jump helpers
  --------------------------------------------------------------------
  signal br_take          : std_logic;
  signal branch_target    : std_logic_vector(31 downto 0);
  signal jalr_target      : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Load / store helpers
  --------------------------------------------------------------------
  signal byte_offset       : std_logic_vector(1 downto 0);
  signal load_data_aligned : std_logic_vector(31 downto 0);
  signal dmem_data_in      : std_logic_vector(31 downto 0);
  signal calc_mem_addr     : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- CSR / trap
  --------------------------------------------------------------------
  signal csr_wdata        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_rdata        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_zimm         : std_logic_vector(31 downto 0);

  signal csr_mstatus      : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mie          : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mip          : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mtvec        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mepc         : std_logic_vector(31 downto 0) := (others => '0');

  signal trap_enter       : std_logic := '0';
  signal trap_pc_in       : std_logic_vector(31 downto 0) := (others => '0');
  signal trap_cause_in    : std_logic_vector(31 downto 0) := (others => '0');
  signal mret_exec        : std_logic := '0';

  signal take_timer_irq   : std_logic;
  signal trap_cause_sel   : std_logic_vector(31 downto 0);

  signal watchdog_reset   : std_logic := '0';

  signal cpu_dmem_we      : std_logic := '0';
  signal cpu_dmem_addr    : std_logic_vector(31 downto 0) := (others => '0');
  signal cpu_dmem_wdata   : std_logic_vector(31 downto 0) := (others => '0');

begin

  --------------------------------------------------------------------
  -- PC path with optional TMR voter and optional fault injection
  --------------------------------------------------------------------
  gen_pc_tmr : if G_PC_TMR generate
    pc_tmr : entity work.tmr_fault_voter
      generic map(
        WIDTH          => 32,
        G_FAULT_INJECT => G_FAULT_INJECT
      )
      port map(
        data_a_i   => pc_a,
        data_b_i   => pc_b,
        data_c_i   => pc_c,
        fi_mask_i   => fi_pc_mask_i,
        fi_target_i => fi_pc_target_i,
        fi_strobe_i => fi_pc_strobe_i,
        voted_o     => pc_v,
        tmr_error_o => pc_tmr_error
      );
  end generate;

  gen_pc_plain : if not G_PC_TMR generate
    pc_v         <= pc_a;
    pc_tmr_error <= '0';
  end generate;

  --------------------------------------------------------------------
  -- State path with optional TMR voter and optional fault injection
  --------------------------------------------------------------------
  state_enc_a <= state_to_slv(state_a);
  state_enc_b <= state_to_slv(state_b);
  state_enc_c <= state_to_slv(state_c);

  gen_state_tmr : if G_STATE_TMR generate
    state_tmr : entity work.tmr_fault_voter
      generic map(
        WIDTH          => 4,
        G_FAULT_INJECT => G_FAULT_INJECT
      )
      port map(
        data_a_i   => state_enc_a,
        data_b_i   => state_enc_b,
        data_c_i   => state_enc_c,
        fi_mask_i   => fi_state_mask_i,
        fi_target_i => fi_state_target_i,
        fi_strobe_i => fi_state_strobe_i,
        voted_o     => state_v_slv,
        tmr_error_o => state_tmr_error
      );
  end generate;

  gen_state_plain : if not G_STATE_TMR generate
    state_v_slv     <= state_enc_a;
    state_tmr_error <= '0';
  end generate;

  state_v <= slv_to_state(state_v_slv);

  --------------------------------------------------------------------
  -- Top-level output muxes
  --------------------------------------------------------------------
  imem_pc    <= pc_v;
  dmem_we    <= cpu_dmem_we;
  dmem_addr  <= cpu_dmem_addr;
  dmem_wdata <= cpu_dmem_wdata;

  --------------------------------------------------------------------
  -- Common derived signals
  --------------------------------------------------------------------
  pc_plus4      <= std_logic_vector(unsigned(instr_pc) + 4);
  calc_mem_addr <= std_logic_vector(unsigned(cur_rs1_val) + unsigned(cur_imm));
  byte_offset   <= mem_addr_reg(1 downto 0);
  branch_target <= std_logic_vector(unsigned(instr_pc) + unsigned(cur_imm));
  jalr_target   <= std_logic_vector((unsigned(cur_rs1_val) + unsigned(cur_imm)) and x"FFFFFFFE");

  take_timer_irq <= '1' when (csr_mstatus(3) = '1' and csr_mie(7) = '1' and csr_mip(7) = '1') else '0';

  trap_cause_sel <= x"00000002" when cur_illegal='1' else
                    x"00000003" when cur_is_ebreak='1' else
                    x"0000000B" when cur_is_ecall='1' else
                    x"80000007";

  csr_zimm  <= (31 downto 5 => '0') & cur_rs1_addr;
  csr_wdata <= csr_zimm when cur_csr_use_imm = '1' else cur_rs1_val;

  --------------------------------------------------------------------
  -- Decoder
  --------------------------------------------------------------------
  decoder_inst : entity work.decoder
    port map(
      instr          => instr_reg,
      rs1            => rs1,
      rs2            => rs2,
      rd             => rd,
      imm            => imm,
      alu_op         => alu_op,
      alu_src        => alu_src,
      reg_write      => reg_write_dec,
      mem_write      => mem_write_dec,
      mem_read       => mem_read_dec,
      mem_to_reg     => mem_to_reg_dec,
      branch         => branch_dec,
      branch_type    => branch_type,
      jump           => jump_dec,
      jalr           => jalr_dec,
      is_auipc       => is_auipc,
      load_size      => load_size,
      load_sign      => load_sign,
      store_size     => store_size,
      is_ecall       => is_ecall,
      is_ebreak      => is_ebreak,
      is_mret        => is_mret,
      illegal_instr  => illegal_instr,
      csr_en         => csr_en,
      csr_we         => csr_we,
      csr_addr       => csr_addr,
      csr_use_imm    => csr_use_imm,
      csr_cmd        => csr_cmd
    );

  --------------------------------------------------------------------
  -- Register file
  --------------------------------------------------------------------
  regfile_inst : entity work.regfile
    generic map(
      G_FAULT_INJECT => G_FAULT_INJECT,
      G_TMR          => G_RF_TMR,
      G_SELF_HEAL    => G_RF_SELF_HEAL
    )
    port map(
      clk                 => clk,
      rst                 => reset,
      we                  => rf_we,
      reg_in_data         => rf_wdata,
      reg_read_addr1      => cur_rs1_addr,
      reg_read_addr2      => cur_rs2_addr,
      reg_write_addr      => rf_waddr,
      reg_out_data1       => reg_rs1,
      reg_out_data2       => reg_rs2,
      regfile_tmr_error_o => regfile_tmr_error,
      fi_rf_mask_i        => fi_rf_mask_i,
      fi_rf_addr_i        => fi_rf_addr_i,
      fi_rf_target_i      => fi_rf_target_i,
      fi_rf_strobe_i      => fi_rf_strobe_i
    );

  --------------------------------------------------------------------
  -- CSR file
  --------------------------------------------------------------------
  csr_inst : entity work.csr_file
    port map(
      clk                      => clk,
      rst                      => reset,
      csr_en                   => cur_csr_en,
      csr_we                   => cur_csr_we,
      csr_addr                 => cur_csr_addr,
      csr_wdata                => csr_wdata,
      csr_cmd                  => cur_csr_cmd,
      csr_rdata                => csr_rdata,
      trap_enter               => trap_enter,
      trap_pc_in               => trap_pc_in,
      trap_cause_in            => trap_cause_in,
      mret_exec                => mret_exec,
      timer_irq_i              => irq_timer_i,
      pc_tmr_error_i           => pc_tmr_error,
      state_tmr_error_i        => state_tmr_error,
      csr_tmr_error_i          => regfile_tmr_error,
      watchdog_reset_o         => watchdog_reset,
      mtvec_out                => csr_mtvec,
      mie_out                  => csr_mie,
      mip_out                  => csr_mip,
      mstatus_out              => csr_mstatus,
      mepc_out                 => csr_mepc,
      dmem_ecc_single_error_i  => dmem_ecc_single_error_i,
      dmem_ecc_double_error_i  => dmem_ecc_double_error_i,
      imem_ecc_single_error_i  => imem_ecc_single_error_i,
      imem_ecc_double_error_i  => imem_ecc_double_error_i
    );

  --------------------------------------------------------------------
  -- ALU
  --------------------------------------------------------------------
  alu_a <= instr_pc when cur_is_auipc = '1' else cur_rs1_val;
  alu_b <= cur_imm  when cur_alu_src  = '1' else cur_rs2_val;

  alu_inst : entity work.alu
    port map(
      a      => alu_a,
      b      => alu_b,
      alu_op => cur_alu_op,
      result => alu_result,
      zero   => open
    );

  --------------------------------------------------------------------
  -- Branch comparator
  --------------------------------------------------------------------
  process(cur_branch, cur_branch_ty, cur_rs1_val, cur_rs2_val)
  begin
    br_take <= '0';

    if cur_branch = '1' then
      case cur_branch_ty is
        when "000" => if cur_rs1_val = cur_rs2_val then br_take <= '1'; end if;
        when "001" => if cur_rs1_val /= cur_rs2_val then br_take <= '1'; end if;
        when "010" => if signed(cur_rs1_val) <  signed(cur_rs2_val) then br_take <= '1'; end if;
        when "011" => if signed(cur_rs1_val) >= signed(cur_rs2_val) then br_take <= '1'; end if;
        when "100" => if unsigned(cur_rs1_val) <  unsigned(cur_rs2_val) then br_take <= '1'; end if;
        when "101" => if unsigned(cur_rs1_val) >= unsigned(cur_rs2_val) then br_take <= '1'; end if;
        when others => null;
      end case;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Store data formatting
  --------------------------------------------------------------------
  lsu_inst : entity work.load_store_unit
    port map(
      dmem_rdata_i  => dmem_rdata,
      rs2_i         => cur_rs2_val,
      byte_offset_i => byte_offset,
      load_size_i   => cur_load_size,
      load_sign_i   => cur_load_sign,
      store_size_i  => cur_store_size,
      load_data_o   => load_data_aligned,
      store_data_o  => dmem_data_in
    );

  --------------------------------------------------------------------
  -- CPU-side data memory outputs
  --------------------------------------------------------------------
  cpu_dmem_we    <= '1' when state_v = ST_MEM_WRITE else '0';
  cpu_dmem_addr  <= calc_mem_addr when (state_v = ST_EXEC_LOAD_ADDR or state_v = ST_EXEC_STORE_ADDR) else mem_addr_reg;
  cpu_dmem_wdata <= dmem_data_in;

  --------------------------------------------------------------------
  -- Main FSM
  --------------------------------------------------------------------
  process(clk)
    procedure set_pc_all(v : std_logic_vector(31 downto 0)) is
    begin
      pc_a <= v;
      if G_PC_TMR then
        pc_b <= v;
        pc_c <= v;
      end if;
    end procedure;

    procedure set_state_all(v : state_t) is
    begin
      state_a <= v;
      if G_STATE_TMR then
        state_b <= v;
        state_c <= v;
      end if;
    end procedure;
  begin
    if rising_edge(clk) then

      rf_we           <= '0';
      rf_waddr        <= (others => '0');
      rf_wdata        <= (others => '0');

      trap_enter      <= '0';
      trap_pc_in      <= (others => '0');
      trap_cause_in   <= (others => '0');
      mret_exec       <= '0';

      if reset = '1' then
        set_state_all(ST_RESET);

        set_pc_all((others => '0'));

        instr_reg       <= NOP;
        instr_pc        <= (others => '0');

        cur_rs1_addr    <= (others => '0');
        cur_rs2_addr    <= (others => '0');
        cur_rd_addr     <= (others => '0');

        cur_rs1_val     <= (others => '0');
        cur_rs2_val     <= (others => '0');
        cur_imm         <= (others => '0');

        cur_alu_op      <= (others => '0');
        cur_alu_src     <= '0';
        cur_branch_ty   <= (others => '0');

        cur_reg_write   <= '0';
        cur_mem_write   <= '0';
        cur_mem_read    <= '0';
        cur_mem_to_reg  <= '0';
        cur_jump        <= '0';
        cur_jalr        <= '0';
        cur_branch      <= '0';
        cur_is_auipc    <= '0';

        cur_load_size   <= "10";
        cur_load_sign   <= '1';
        cur_store_size  <= "10";

        cur_is_ecall    <= '0';
        cur_is_ebreak   <= '0';
        cur_is_mret     <= '0';
        cur_illegal     <= '0';

        cur_csr_en      <= '0';
        cur_csr_we      <= '0';
        cur_csr_addr    <= (others => '0');
        cur_csr_use_imm <= '0';
        cur_csr_cmd     <= "11";

        exec_result     <= (others => '0');
        mem_addr_reg    <= (others => '0');
        load_data_reg   <= (others => '0');
        csr_read_reg    <= (others => '0');
        next_pc_reg     <= (others => '0');

      else
        case state_v is

            when ST_RESET =>
              set_pc_all((others => '0'));
              set_state_all(ST_FETCH);

            when ST_FETCH =>
              set_state_all(ST_FETCH_WAIT);

            when ST_FETCH_WAIT =>
              instr_pc  <= pc_v;
              instr_reg <= imem_instr;

              set_state_all(ST_DECODE);

            when ST_DECODE =>
              cur_rs1_addr    <= rs1;
              cur_rs2_addr    <= rs2;
              cur_rd_addr     <= rd;

              cur_imm         <= imm;

              cur_alu_op      <= alu_op;
              cur_alu_src     <= alu_src;
              cur_branch_ty   <= branch_type;

              cur_reg_write   <= reg_write_dec;
              cur_mem_write   <= mem_write_dec;
              cur_mem_read    <= mem_read_dec;
              cur_mem_to_reg  <= mem_to_reg_dec;
              cur_jump        <= jump_dec;
              cur_jalr        <= jalr_dec;
              cur_branch      <= branch_dec;
              cur_is_auipc    <= is_auipc;

              cur_load_size   <= load_size;
              cur_load_sign   <= load_sign;
              cur_store_size  <= store_size;

              cur_is_ecall    <= is_ecall;
              cur_is_ebreak   <= is_ebreak;
              cur_is_mret     <= is_mret;
              cur_illegal     <= illegal_instr;

              cur_csr_en      <= csr_en;
              cur_csr_we      <= csr_we;
              cur_csr_addr    <= csr_addr;
              cur_csr_use_imm <= csr_use_imm;
              cur_csr_cmd     <= csr_cmd;

              next_pc_reg     <= std_logic_vector(unsigned(pc_v) + 4);

              set_state_all(ST_RF_WAIT);

            when ST_RF_WAIT =>
              cur_rs1_val <= reg_rs1;
              cur_rs2_val <= reg_rs2;

              if cur_illegal = '1' or cur_is_ebreak = '1' or cur_is_ecall = '1' or take_timer_irq = '1' then
                set_state_all(ST_TRAP);
              elsif cur_is_mret = '1' then
                set_state_all(ST_MRET);
              elsif cur_csr_en = '1' then
                set_state_all(ST_EXEC_CSR);
              elsif cur_mem_read = '1' then
                set_state_all(ST_EXEC_LOAD_ADDR);
              elsif cur_mem_write = '1' then
                set_state_all(ST_EXEC_STORE_ADDR);
              elsif cur_branch = '1' then
                set_state_all(ST_EXEC_BRANCH);
              elsif cur_jump = '1' or cur_jalr = '1' then
                set_state_all(ST_EXEC_JUMP);
              else
                set_state_all(ST_EXEC_ALU);
              end if;

            when ST_EXEC_ALU =>
              exec_result <= alu_result;

              set_state_all(ST_WB);

            when ST_EXEC_LOAD_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              set_state_all(ST_MEM_READ);

            when ST_EXEC_STORE_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              set_state_all(ST_MEM_WRITE);

            when ST_EXEC_BRANCH =>
              if br_take = '1' then
                set_pc_all(branch_target);
              else
                set_pc_all(next_pc_reg);
              end if;

              set_state_all(ST_FETCH);

            when ST_EXEC_JUMP =>
              exec_result <= pc_plus4;

              if cur_jalr = '1' then
                set_pc_all(jalr_target);
              else
                set_pc_all(branch_target);
              end if;

              set_state_all(ST_WB);

            when ST_EXEC_CSR =>
              csr_read_reg <= csr_rdata;

              set_state_all(ST_WB);

            when ST_MEM_READ =>
              load_data_reg <= load_data_aligned;

              set_state_all(ST_WB);

            when ST_MEM_WRITE =>
              set_pc_all(next_pc_reg);

              set_state_all(ST_FETCH);

            when ST_TRAP =>
              trap_enter    <= '1';
              trap_pc_in    <= instr_pc;
              trap_cause_in <= trap_cause_sel;

              set_pc_all(csr_mtvec);

              set_state_all(ST_FETCH);

            when ST_MRET =>
              mret_exec <= '1';

              set_pc_all(csr_mepc);

              set_state_all(ST_FETCH);

            when ST_WB =>
              if cur_reg_write = '1' and cur_rd_addr /= "00000" then
                rf_we    <= '1';
                rf_waddr <= cur_rd_addr;

                if cur_csr_en = '1' then
                  rf_wdata <= csr_read_reg;
                elsif cur_jump = '1' or cur_jalr = '1' then
                  rf_wdata <= exec_result;
                elsif cur_mem_read = '1' then
                  rf_wdata <= load_data_reg;
                else
                  rf_wdata <= exec_result;
                end if;
              end if;

              if cur_jump = '0' and cur_jalr = '0' then
                set_pc_all(next_pc_reg);
              end if;

              set_state_all(ST_FETCH);

            when others =>
              set_state_all(ST_FETCH);

        end case;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Optional debug
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if state_tmr_error = '1' then
        report "STATE TMR ERROR seen in core" severity note;
      end if;

      if pc_tmr_error = '1' then
        report "PC TMR ERROR seen in core" severity note;
      end if;

      if regfile_tmr_error = '1' then
        report "REGFILE TMR ERROR seen in core (self-healing active)" severity note;
      end if;
    end if;
  end process;

  watchdog_reset_o <= watchdog_reset;
  pc_tmr_error_o      <= pc_tmr_error;
  state_tmr_error_o   <= state_tmr_error;
  regfile_tmr_error_o <= regfile_tmr_error;

end rtl;

