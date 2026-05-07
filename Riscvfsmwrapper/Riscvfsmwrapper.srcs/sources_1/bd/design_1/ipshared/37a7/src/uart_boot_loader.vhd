library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_boot_loader is
  port(
    clk   : in std_logic;
    reset : in std_logic;

    rx_byte_i  : in std_logic_vector(7 downto 0);
    rx_valid_i : in std_logic;

    imem_prog_we_o    : out std_logic;
    imem_prog_addr_o  : out std_logic_vector(31 downto 0);
    imem_prog_wdata_o : out std_logic_vector(31 downto 0);

    dmem_prog_we_o    : out std_logic;
    dmem_prog_addr_o  : out std_logic_vector(31 downto 0);
    dmem_prog_wdata_o : out std_logic_vector(31 downto 0);

    done_o : out std_logic
  );
end entity;

architecture rtl of uart_boot_loader is

  type state_t is (
    WAIT_55,
    WAIT_AA,
    IMEM_LEN0,
    IMEM_LEN1,
    IMEM_LEN2,
    IMEM_LEN3,
    DMEM_LEN0,
    DMEM_LEN1,
    DMEM_LEN2,
    DMEM_LEN3,
    IMEM_DATA,
    DMEM_DATA,
    DONE
  );

  signal state : state_t := WAIT_55;

  signal imem_length_bytes : unsigned(31 downto 0) := (others => '0');
  signal dmem_length_bytes : unsigned(31 downto 0) := (others => '0');
  signal dmem_length_full  : unsigned(31 downto 0) := (others => '0');
  signal bytes_rcvd        : unsigned(31 downto 0) := (others => '0');

  signal word_buf     : std_logic_vector(31 downto 0) := (others => '0');
  signal byte_in_word : integer range 0 to 3 := 0;
  signal word_index   : unsigned(31 downto 0) := (others => '0');

  signal imem_we_r    : std_logic := '0';
  signal imem_addr_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal imem_wdata_r : std_logic_vector(31 downto 0) := (others => '0');

  signal dmem_we_r    : std_logic := '0';
  signal dmem_addr_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal dmem_wdata_r : std_logic_vector(31 downto 0) := (others => '0');

  signal done_r : std_logic := '0';

begin

  imem_prog_we_o    <= imem_we_r;
  imem_prog_addr_o  <= imem_addr_r;
  imem_prog_wdata_o <= imem_wdata_r;
  dmem_prog_we_o    <= dmem_we_r;
  dmem_prog_addr_o  <= dmem_addr_r;
  dmem_prog_wdata_o <= dmem_wdata_r;
  done_o            <= done_r;

  process(clk)
    variable next_word      : std_logic_vector(31 downto 0);
    variable dmem_len_local : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      imem_we_r <= '0';
      dmem_we_r <= '0';

      if reset = '1' then
        state              <= WAIT_55;
        imem_length_bytes  <= (others => '0');
        dmem_length_bytes  <= (others => '0');
        dmem_length_full   <= (others => '0');
        bytes_rcvd         <= (others => '0');
        word_buf           <= (others => '0');
        byte_in_word       <= 0;
        word_index         <= (others => '0');
        imem_we_r          <= '0';
        imem_addr_r        <= (others => '0');
        imem_wdata_r       <= (others => '0');
        dmem_we_r          <= '0';
        dmem_addr_r        <= (others => '0');
        dmem_wdata_r       <= (others => '0');
        done_r             <= '0';
      else
        case state is

          when WAIT_55 =>
            done_r <= '0';
            if rx_valid_i = '1' and rx_byte_i = x"55" then
              state <= WAIT_AA;
            end if;

          when WAIT_AA =>
            if rx_valid_i = '1' then
              if rx_byte_i = x"AA" then
                state <= IMEM_LEN0;
              else
                state <= WAIT_55;
              end if;
            end if;

          when IMEM_LEN0 =>
            if rx_valid_i = '1' then
              imem_length_bytes(7 downto 0) <= unsigned(rx_byte_i);
              state <= IMEM_LEN1;
            end if;

          when IMEM_LEN1 =>
            if rx_valid_i = '1' then
              imem_length_bytes(15 downto 8) <= unsigned(rx_byte_i);
              state <= IMEM_LEN2;
            end if;

          when IMEM_LEN2 =>
            if rx_valid_i = '1' then
              imem_length_bytes(23 downto 16) <= unsigned(rx_byte_i);
              state <= IMEM_LEN3;
            end if;

          when IMEM_LEN3 =>
            if rx_valid_i = '1' then
              imem_length_bytes(31 downto 24) <= unsigned(rx_byte_i);
              state <= DMEM_LEN0;
            end if;

          when DMEM_LEN0 =>
            if rx_valid_i = '1' then
              dmem_length_bytes(7 downto 0) <= unsigned(rx_byte_i);
              state <= DMEM_LEN1;
            end if;

          when DMEM_LEN1 =>
            if rx_valid_i = '1' then
              dmem_length_bytes(15 downto 8) <= unsigned(rx_byte_i);
              state <= DMEM_LEN2;
            end if;

          when DMEM_LEN2 =>
            if rx_valid_i = '1' then
              dmem_length_bytes(23 downto 16) <= unsigned(rx_byte_i);
              state <= DMEM_LEN3;
            end if;

          when DMEM_LEN3 =>
            if rx_valid_i = '1' then
              dmem_len_local := unsigned(rx_byte_i) & dmem_length_bytes(23 downto 0);

              dmem_length_bytes(31 downto 24) <= unsigned(rx_byte_i);
              dmem_length_full                <= dmem_len_local;

              bytes_rcvd   <= (others => '0');
              word_index   <= (others => '0');
              byte_in_word <= 0;
              word_buf     <= (others => '0');

              if imem_length_bytes = 0 then
                if dmem_len_local = 0 then
                  state  <= DONE;
                  done_r <= '1';
                else
                  state <= DMEM_DATA;
                end if;
              else
                state <= IMEM_DATA;
              end if;
            end if;

          when IMEM_DATA =>
            if rx_valid_i = '1' then
              next_word := word_buf;

              case byte_in_word is
                when 0      => next_word(7 downto 0)   := rx_byte_i;
                when 1      => next_word(15 downto 8)  := rx_byte_i;
                when 2      => next_word(23 downto 16) := rx_byte_i;
                when others => next_word(31 downto 24) := rx_byte_i;
              end case;

              word_buf   <= next_word;
              bytes_rcvd <= bytes_rcvd + 1;

              if byte_in_word = 3 then
                imem_we_r    <= '1';
                imem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                imem_wdata_r <= next_word;
                word_index   <= word_index + 1;
                byte_in_word <= 0;
                word_buf     <= (others => '0');
              else
                byte_in_word <= byte_in_word + 1;
              end if;

              if (bytes_rcvd + 1) = imem_length_bytes then
                if byte_in_word /= 3 then
                  imem_we_r    <= '1';
                  imem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                  imem_wdata_r <= next_word;
                end if;

                bytes_rcvd   <= (others => '0');
                word_index   <= (others => '0');
                byte_in_word <= 0;
                word_buf     <= (others => '0');

                if dmem_length_full = 0 then
                  state  <= DONE;
                  done_r <= '1';
                else
                  state <= DMEM_DATA;
                end if;
              end if;
            end if;

          when DMEM_DATA =>
            if rx_valid_i = '1' then
              next_word := word_buf;

              case byte_in_word is
                when 0      => next_word(7 downto 0)   := rx_byte_i;
                when 1      => next_word(15 downto 8)  := rx_byte_i;
                when 2      => next_word(23 downto 16) := rx_byte_i;
                when others => next_word(31 downto 24) := rx_byte_i;
              end case;

              word_buf   <= next_word;
              bytes_rcvd <= bytes_rcvd + 1;

              if byte_in_word = 3 then
                dmem_we_r    <= '1';
                dmem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                dmem_wdata_r <= next_word;
                word_index   <= word_index + 1;
                byte_in_word <= 0;
                word_buf     <= (others => '0');
              else
                byte_in_word <= byte_in_word + 1;
              end if;

              if (bytes_rcvd + 1) = dmem_length_full then
                if byte_in_word /= 3 then
                  dmem_we_r    <= '1';
                  dmem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                  dmem_wdata_r <= next_word;
                end if;

                state  <= DONE;
                done_r <= '1';
              end if;
            end if;

          when DONE =>
            done_r <= '1';

        end case;
      end if;
    end if;
  end process;

end rtl;
