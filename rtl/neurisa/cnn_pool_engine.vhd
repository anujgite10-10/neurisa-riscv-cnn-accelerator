-- ================================================================================
-- NeurISA — 2×2 Pooling Engine (Max-Pool & Average-Pool)
-- ================================================================================
-- Performs 2×2 spatial pooling on INT8 feature maps.
-- Supports max-pooling (default) and average-pooling (configurable).
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cnn_pool_engine is
  generic (
    DATA_WIDTH : natural := 8
  );
  port (
    clk_i          : in  std_ulogic;
    rstn_i         : in  std_ulogic;
    -- Control --
    start_i        : in  std_ulogic;
    mode_i         : in  std_ulogic;  -- '0' = max-pool, '1' = avg-pool
    done_o         : out std_ulogic;
    busy_o         : out std_ulogic;
    -- Input: 4 pixels (2×2 window), loaded sequentially --
    pixel_data_i   : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    pixel_valid_i  : in  std_ulogic;
    -- Output --
    result_o       : out std_ulogic_vector(DATA_WIDTH-1 downto 0);
    result_valid_o : out std_ulogic
  );
end cnn_pool_engine;

architecture rtl of cnn_pool_engine is

  type pixel_buf_t is array (0 to 3) of signed(DATA_WIDTH-1 downto 0);
  signal pixel_buf   : pixel_buf_t;
  signal pixel_count : unsigned(1 downto 0);
  signal buf_full    : std_ulogic;

  -- Max-pool signals
  signal max_01, max_23 : signed(DATA_WIDTH-1 downto 0);
  signal max_all        : signed(DATA_WIDTH-1 downto 0);

  -- Avg-pool signals
  signal avg_sum : signed(DATA_WIDTH+1 downto 0); -- 10-bit for sum of 4 INT8
  signal avg_val : signed(DATA_WIDTH-1 downto 0);

  type state_t is (IDLE, COMPUTE, OUTPUT_ST);
  signal state : state_t;

begin

  -- ============================================================
  -- Pixel Buffer Loading
  -- ============================================================
  load_proc: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      pixel_buf   <= (others => (others => '0'));
      pixel_count <= (others => '0');
      buf_full    <= '0';
    elsif rising_edge(clk_i) then
      buf_full <= '0';
      if start_i = '1' then
        pixel_count <= (others => '0');
      end if;
      if pixel_valid_i = '1' then
        pixel_buf(to_integer(pixel_count)) <= signed(pixel_data_i);
        pixel_count <= pixel_count + 1;
        if pixel_count = "11" then
          buf_full    <= '1';
          pixel_count <= (others => '0');
        end if;
      end if;
    end if;
  end process load_proc;

  -- ============================================================
  -- Max-Pool (combinatorial)
  -- ============================================================
  max_01  <= pixel_buf(0) when pixel_buf(0) >= pixel_buf(1) else pixel_buf(1);
  max_23  <= pixel_buf(2) when pixel_buf(2) >= pixel_buf(3) else pixel_buf(3);
  max_all <= max_01 when max_01 >= max_23 else max_23;

  -- ============================================================
  -- Average-Pool (combinatorial) — sum/4 via shift
  -- ============================================================
  avg_sum <= resize(pixel_buf(0), DATA_WIDTH+2) + resize(pixel_buf(1), DATA_WIDTH+2) +
             resize(pixel_buf(2), DATA_WIDTH+2) + resize(pixel_buf(3), DATA_WIDTH+2);
  avg_val <= avg_sum(DATA_WIDTH+1 downto 2); -- divide by 4 (arithmetic shift right 2)

  -- ============================================================
  -- Pooling FSM
  -- ============================================================
  pool_fsm: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      state          <= IDLE;
      done_o         <= '0';
      busy_o         <= '0';
      result_o       <= (others => '0');
      result_valid_o <= '0';
    elsif rising_edge(clk_i) then
      done_o         <= '0';
      result_valid_o <= '0';

      case state is
        when IDLE =>
          busy_o <= '0';
          if buf_full = '1' then
            state  <= COMPUTE;
            busy_o <= '1';
          end if;

        when COMPUTE =>
          if mode_i = '0' then
            result_o <= std_ulogic_vector(max_all);
          else
            result_o <= std_ulogic_vector(avg_val);
          end if;
          state <= OUTPUT_ST;

        when OUTPUT_ST =>
          done_o         <= '1';
          result_valid_o <= '1';
          busy_o         <= '0';
          state          <= IDLE;

        when others =>
          state <= IDLE;
      end case;
    end if;
  end process pool_fsm;

end rtl;
