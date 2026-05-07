library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity riscv_core_memless is
  generic(
    G_DEBUG_LOG       : boolean := false;
    G_DEBUG_GP_LOG    : boolean := false
  );
  port(
    clk   : in  std_logic;
    reset : in  std_logic;
    ce_i  : in  std_logic := '1';

    -- Encoded current state for the LiteX/Wishbone wrapper
    state_dbg_o : out std_logic_vector(3 downto 0);

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

    -- Watchdog reset pulse from CSR block
    watchdog_reset_o : out std_logic
  );
end riscv_core_memless;

architecture rtl of riscv_core_memless is

  --------------------------------------------------------------------
  -- Core state
  --------------------------------------------------------------------
  signal state            : state_t := ST_RESET;
  signal state_dbg        : std_logic_vector(3 downto 0) := "0000";

  signal pc               : std_logic_vector(31 downto 0) := (others => '0');

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
  signal reg_rs1           : std_logic_vector(31 downto 0);
  signal reg_rs2           : std_logic_vector(31 downto 0);

  signal rf_we             : std_logic := '0';
  signal rf_waddr          : std_logic_vector(4 downto 0) := (others => '0');
  signal rf_wdata          : std_logic_vector(31 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- Latched instruction context
  --------------------------------------------------------------------
  signal cur_ctl_v         : std_logic_vector(CUR_CTL_W-1 downto 0) := CUR_CTL_RESET;

  signal cur_rs1_addr      : std_logic_vector(4 downto 0);
  signal cur_rs2_addr      : std_logic_vector(4 downto 0);
  signal cur_rd_addr       : std_logic_vector(4 downto 0);

  signal cur_rs1_val       : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_rs2_val       : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_imm           : std_logic_vector(31 downto 0);

  signal cur_alu_op        : std_logic_vector(3 downto 0);
  signal cur_alu_src       : std_logic;
  signal cur_branch_ty     : std_logic_vector(2 downto 0);

  signal cur_reg_write     : std_logic;
  signal cur_mem_write     : std_logic;
  signal cur_mem_read      : std_logic;
  signal cur_mem_to_reg    : std_logic;
  signal cur_jump          : std_logic;
  signal cur_jalr          : std_logic;
  signal cur_branch        : std_logic;
  signal cur_is_auipc      : std_logic;

  signal cur_load_size     : std_logic_vector(1 downto 0);
  signal cur_load_sign     : std_logic;
  signal cur_store_size    : std_logic_vector(1 downto 0);

  signal cur_is_ecall      : std_logic;
  signal cur_is_ebreak     : std_logic;
  signal cur_is_mret       : std_logic;
  signal cur_illegal       : std_logic;

  signal cur_csr_en        : std_logic;
  signal cur_csr_we        : std_logic;
  signal cur_csr_addr      : std_logic_vector(11 downto 0);
  signal cur_csr_use_imm   : std_logic;
  signal cur_csr_cmd       : std_logic_vector(1 downto 0);

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
  signal wb_data_sel      : std_logic_vector(31 downto 0) := (others => '0');

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

  --------------------------------------------------------------------
  -- Accelerator MMIO
  --------------------------------------------------------------------
  signal acc_a_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_b_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_c_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_m            : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_n            : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_k            : std_logic_vector(31 downto 0) := (others => '0');

  signal acc_start_pulse  : std_logic := '0';
  signal acc_busy         : std_logic := '0';
  signal acc_done_raw     : std_logic := '0';
  signal acc_done_sticky  : std_logic := '0';

  signal is_mmio_addr     : std_logic;
  signal is_acc_addr      : std_logic;
  signal acc_reg_rdata    : std_logic_vector(31 downto 0);
  signal dmem_rdata_eff   : std_logic_vector(31 downto 0);

  signal cpu_dmem_we      : std_logic := '0';
  signal cpu_dmem_addr    : std_logic_vector(31 downto 0) := (others => '0');
  signal cpu_dmem_wdata   : std_logic_vector(31 downto 0) := (others => '0');

  signal acc_dmem_we      : std_logic;
  signal acc_dmem_addr    : std_logic_vector(31 downto 0);
  signal acc_dmem_wdata   : std_logic_vector(31 downto 0);
  
begin

  --------------------------------------------------------------------
  -- Debug state encoding
  --------------------------------------------------------------------
  state_dbg <= state_to_slv(state);

  --------------------------------------------------------------------
  -- Unpack latched decode/control bundle
  --------------------------------------------------------------------
  cur_rs1_addr    <= cur_ctl_v(88 downto 84);
  cur_rs2_addr    <= cur_ctl_v(83 downto 79);
  cur_rd_addr     <= cur_ctl_v(78 downto 74);
  cur_imm         <= cur_ctl_v(73 downto 42);
  cur_alu_op      <= cur_ctl_v(41 downto 38);
  cur_alu_src     <= cur_ctl_v(37);
  cur_branch_ty   <= cur_ctl_v(36 downto 34);
  cur_reg_write   <= cur_ctl_v(33);
  cur_mem_write   <= cur_ctl_v(32);
  cur_mem_read    <= cur_ctl_v(31);
  cur_mem_to_reg  <= cur_ctl_v(30);
  cur_jump        <= cur_ctl_v(29);
  cur_jalr        <= cur_ctl_v(28);
  cur_branch      <= cur_ctl_v(27);
  cur_is_auipc    <= cur_ctl_v(26);
  cur_load_size   <= cur_ctl_v(25 downto 24);
  cur_load_sign   <= cur_ctl_v(23);
  cur_store_size  <= cur_ctl_v(22 downto 21);
  cur_is_ecall    <= cur_ctl_v(20);
  cur_is_ebreak   <= cur_ctl_v(19);
  cur_is_mret     <= cur_ctl_v(18);
  cur_illegal     <= cur_ctl_v(17);
  cur_csr_en      <= cur_ctl_v(16);
  cur_csr_we      <= cur_ctl_v(15);
  cur_csr_addr    <= cur_ctl_v(14 downto 3);
  cur_csr_use_imm <= cur_ctl_v(2);
  cur_csr_cmd     <= cur_ctl_v(1 downto 0);

  --------------------------------------------------------------------
  -- Top-level output muxes
  --------------------------------------------------------------------
  imem_pc    <= pc;
  dmem_we    <= acc_dmem_we    when acc_busy = '1' else cpu_dmem_we;
  dmem_addr  <= acc_dmem_addr  when acc_busy = '1' else cpu_dmem_addr;
  dmem_wdata <= acc_dmem_wdata when acc_busy = '1' else cpu_dmem_wdata;

  --------------------------------------------------------------------
  -- Common derived signals
  --------------------------------------------------------------------
  pc_plus4      <= std_logic_vector(unsigned(instr_pc) + 4);
  calc_mem_addr <= std_logic_vector(unsigned(cur_rs1_val) + unsigned(cur_imm));
  byte_offset   <= mem_addr_reg(1 downto 0);
  branch_target <= std_logic_vector(unsigned(instr_pc) + unsigned(cur_imm));
  jalr_target   <= std_logic_vector((unsigned(cur_rs1_val) + unsigned(cur_imm)) and x"FFFFFFFE");

  take_timer_irq <= '1' when (csr_mstatus(3) = '1' and csr_mie(7) = '1' and csr_mip(7) = '1') else '0';

  trap_cause_sel <= x"0000000B" when cur_is_ecall='1' else
                    x"00000003" when cur_is_ebreak='1' else
                    x"00000002" when cur_illegal='1' else
                    x"80000007";

  csr_zimm  <= (31 downto 5 => '0') & cur_rs1_addr;
  csr_wdata <= csr_zimm when cur_csr_use_imm = '1' else cur_rs1_val;

  wb_data_sel <= csr_read_reg  when cur_csr_en = '1' else
                 exec_result   when (cur_jump = '1' or cur_jalr = '1') else
                 load_data_reg when cur_mem_read = '1' else
                 exec_result;

  is_mmio_addr <= '1' when mem_addr_reg(31 downto 16) = x"4000"  else '0';
  is_acc_addr  <= '1' when mem_addr_reg(31 downto 12) = x"40000" else '0';

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
    port map(
      clk            => clk,
      rst            => reset,
      we             => rf_we,
      reg_in_data    => rf_wdata,
      reg_read_addr1 => cur_rs1_addr,
      reg_read_addr2 => cur_rs2_addr,
      reg_write_addr => rf_waddr,
      reg_out_data1  => reg_rs1,
      reg_out_data2  => reg_rs2
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
      watchdog_reset_o         => watchdog_reset,
      mtvec_out                => csr_mtvec,
      mie_out                  => csr_mie,
      mip_out                  => csr_mip,
      mstatus_out              => csr_mstatus,
      mepc_out                 => csr_mepc
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
  branch_unit_inst : entity work.branch_unit
    port map(
      branch_i      => cur_branch,
      branch_type_i => cur_branch_ty,
      rs1_i         => cur_rs1_val,
      rs2_i         => cur_rs2_val,
      take_o        => br_take
    );

  --------------------------------------------------------------------
  -- Accelerator MMIO read
  --------------------------------------------------------------------
  process(mem_addr_reg, acc_a_base, acc_b_base, acc_c_base, acc_m, acc_n, acc_k, acc_busy, acc_done_sticky)
  begin
    acc_reg_rdata <= (others => '0');

    case mem_addr_reg(7 downto 0) is
      when x"00" =>
        acc_reg_rdata(1) <= acc_busy;
        acc_reg_rdata(2) <= acc_done_sticky;
      when x"04" => acc_reg_rdata <= acc_a_base;
      when x"08" => acc_reg_rdata <= acc_b_base;
      when x"0C" => acc_reg_rdata <= acc_c_base;
      when x"10" => acc_reg_rdata <= acc_m;
      when x"14" => acc_reg_rdata <= acc_n;
      when x"18" => acc_reg_rdata <= acc_k;
      when others => null;
    end case;
  end process;

  dmem_rdata_eff <= acc_reg_rdata when is_acc_addr = '1' else dmem_rdata;

  --------------------------------------------------------------------
  -- Load/store byte-lane formatting
  --------------------------------------------------------------------
  load_store_unit_inst : entity work.load_store_unit
    port map(
      rs2_i               => cur_rs2_val,
      store_size_i        => cur_store_size,
      load_size_i         => cur_load_size,
      load_sign_i         => cur_load_sign,
      byte_offset_i       => byte_offset,
      dmem_rdata_i        => dmem_rdata_eff,
      store_data_o        => dmem_data_in,
      load_data_aligned_o => load_data_aligned
    );

  --------------------------------------------------------------------
  -- CPU-side data memory outputs
  --------------------------------------------------------------------
  cpu_dmem_we    <= '1' when (state = ST_MEM_WRITE and is_acc_addr = '0') else '0';
  cpu_dmem_addr  <= calc_mem_addr when (state = ST_EXEC_LOAD_ADDR or state = ST_EXEC_STORE_ADDR) else mem_addr_reg;
  cpu_dmem_wdata <= dmem_data_in;

  --------------------------------------------------------------------
  -- Main FSM
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then

      rf_we           <= '0';
      rf_waddr        <= (others => '0');
      rf_wdata        <= (others => '0');

      trap_enter      <= '0';
      trap_pc_in      <= (others => '0');
      trap_cause_in   <= (others => '0');
      mret_exec       <= '0';

      acc_start_pulse <= '0';

      if reset = '1' then
        state           <= ST_RESET;
        pc              <= (others => '0');
        instr_reg       <= NOP;
        instr_pc        <= (others => '0');
        cur_ctl_v       <= CUR_CTL_RESET;

        cur_rs1_val     <= (others => '0');
        cur_rs2_val     <= (others => '0');

        exec_result     <= (others => '0');
        mem_addr_reg    <= (others => '0');
        load_data_reg   <= (others => '0');
        csr_read_reg    <= (others => '0');
        next_pc_reg     <= (others => '0');

        acc_a_base      <= (others => '0');
        acc_b_base      <= (others => '0');
        acc_c_base      <= (others => '0');
        acc_m           <= (others => '0');
        acc_n           <= (others => '0');
        acc_k           <= (others => '0');
        acc_done_sticky <= '0';

      else
        if acc_done_raw = '1' then
          acc_done_sticky <= '1';
        end if;

        if ce_i = '1' then
          if acc_busy = '1' then
            null;
          else
            case state is

            when ST_RESET =>
              pc    <= (others => '0');
              state <= ST_FETCH;

            when ST_FETCH =>
              state <= ST_FETCH_WAIT;

            when ST_FETCH_WAIT =>
              instr_pc <= pc;

              instr_reg <= imem_instr;

              state <= ST_DECODE;

            when ST_DECODE =>
              cur_ctl_v <= pack_cur_ctl(
                             rs1,
                             rs2,
                             rd,
                             imm,
                             alu_op,
                             alu_src,
                             branch_type,
                             reg_write_dec,
                             mem_write_dec,
                             mem_read_dec,
                             mem_to_reg_dec,
                             jump_dec,
                             jalr_dec,
                             branch_dec,
                             is_auipc,
                             load_size,
                             load_sign,
                             store_size,
                             is_ecall,
                             is_ebreak,
                             is_mret,
                             illegal_instr,
                             csr_en,
                             csr_we,
                             csr_addr,
                             csr_use_imm,
                             csr_cmd
                           );

              next_pc_reg <= std_logic_vector(unsigned(pc) + 4);


              state <= ST_RF_WAIT;

            when ST_RF_WAIT =>
              cur_rs1_val <= reg_rs1;
              cur_rs2_val <= reg_rs2;

              if cur_illegal = '1' or cur_is_ebreak = '1' or cur_is_ecall = '1' or take_timer_irq = '1' then
                state <= ST_TRAP;
              elsif cur_is_mret = '1' then
                state <= ST_MRET;
              elsif cur_csr_en = '1' then
                state <= ST_EXEC_CSR;
              elsif cur_mem_read = '1' then
                state <= ST_EXEC_LOAD_ADDR;
              elsif cur_mem_write = '1' then
                state <= ST_EXEC_STORE_ADDR;
              elsif cur_branch = '1' then
                state <= ST_EXEC_BRANCH;
              elsif cur_jump = '1' or cur_jalr = '1' then
                state <= ST_EXEC_JUMP;
              else
                state <= ST_EXEC_ALU;
              end if;

            when ST_EXEC_ALU =>
              exec_result <= alu_result;

              state <= ST_WB;

            when ST_EXEC_LOAD_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              state <= ST_MEM_READ;

            when ST_EXEC_STORE_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              state <= ST_MEM_WRITE;

            when ST_EXEC_BRANCH =>
              if br_take = '1' then
                pc <= branch_target;
              else
                pc <= next_pc_reg;
              end if;

              state <= ST_FETCH;

            when ST_EXEC_JUMP =>
              exec_result <= pc_plus4;

              if cur_jalr = '1' then
                pc <= jalr_target;
              else
                pc <= branch_target;
              end if;

              state <= ST_WB;

            when ST_EXEC_CSR =>
              csr_read_reg <= csr_rdata;

              state <= ST_WB;

            when ST_MEM_READ =>
              load_data_reg <= load_data_aligned;

              state <= ST_WB;

            when ST_MEM_WRITE =>
              if is_acc_addr = '1' then
                case mem_addr_reg(7 downto 0) is
                  when x"00" =>
                    if cur_rs2_val(0) = '1' then
                      acc_start_pulse <= '1';
                      acc_done_sticky <= '0';
                    end if;
                  when x"04" => acc_a_base <= cur_rs2_val;
                  when x"08" => acc_b_base <= cur_rs2_val;
                  when x"0C" => acc_c_base <= cur_rs2_val;
                  when x"10" => acc_m      <= cur_rs2_val;
                  when x"14" => acc_n      <= cur_rs2_val;
                  when x"18" => acc_k      <= cur_rs2_val;
                  when others => null;
                end case;
              end if;

              pc <= next_pc_reg;

              state <= ST_FETCH;

            when ST_TRAP =>
              trap_enter    <= '1';
              trap_pc_in    <= instr_pc;
              trap_cause_in <= trap_cause_sel;

              pc <= csr_mtvec;

              state <= ST_FETCH;

            when ST_MRET =>
              mret_exec <= '1';

              pc <= csr_mepc;

              state <= ST_FETCH;

            when ST_WB =>
              if cur_reg_write = '1' and cur_rd_addr /= "00000" then
                rf_we    <= '1';
                rf_waddr <= cur_rd_addr;
                rf_wdata <= wb_data_sel;

              end if;

              if cur_jump = '0' and cur_jalr = '0' then
                pc <= next_pc_reg;
              end if;

              state <= ST_FETCH;

            when others =>
              state <= ST_FETCH;

            end case;
          end if;
        end if;
      end if;
    end if;
  end process;

  state_dbg_o      <= state_dbg;
  watchdog_reset_o <= watchdog_reset;

end rtl;
