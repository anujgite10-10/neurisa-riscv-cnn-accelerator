-- ================================================================================
-- NeurISA — CNN Layer Controller FSM
-- ================================================================================
-- Orchestrates the convolution, activation, and pooling engines to execute
-- complete CNN layers. Manages sliding window traversal and channel iteration.
--   - Reads layer configuration from CFS registers
--   - Controls weight loading, pixel streaming, and result collection
--   - Supports sequential layer execution
--   - Tracks performance counters (cycles, operations)
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cnn_controller is
  port (
    clk_i             : in  std_ulogic;
    rstn_i            : in  std_ulogic;
    -- Layer configuration --
    cfg_start_i       : in  std_ulogic;                     -- start layer processing
    cfg_input_h_i     : in  std_ulogic_vector(7 downto 0);  -- input height (max 255)
    cfg_input_w_i     : in  std_ulogic_vector(7 downto 0);  -- input width (max 255)
    cfg_input_ch_i    : in  std_ulogic_vector(7 downto 0);  -- input channels
    cfg_output_ch_i   : in  std_ulogic_vector(7 downto 0);  -- output channels
    cfg_stride_i      : in  std_ulogic_vector(1 downto 0);  -- stride (1 or 2)
    cfg_padding_i     : in  std_ulogic;                      -- '1' = same padding
    cfg_act_mode_i    : in  std_ulogic_vector(1 downto 0);  -- activation mode
    cfg_pool_en_i     : in  std_ulogic;                      -- enable pooling
    cfg_pool_mode_i   : in  std_ulogic;                      -- pool mode
    -- Status --
    busy_o            : out std_ulogic;
    done_o            : out std_ulogic;
    layer_idx_o       : out std_ulogic_vector(3 downto 0);   -- current layer index
    -- Performance counters --
    perf_cycles_o     : out std_ulogic_vector(31 downto 0);
    perf_ops_o        : out std_ulogic_vector(31 downto 0);
    -- Convolution engine interface --
    conv_start_o      : out std_ulogic;
    conv_clear_accum_o: out std_ulogic;
    conv_done_i       : in  std_ulogic;
    conv_busy_i       : in  std_ulogic;
    conv_weight_data_o: out std_ulogic_vector(7 downto 0);
    conv_weight_valid_o: out std_ulogic;
    conv_weight_addr_o: out std_ulogic_vector(3 downto 0);
    conv_pixel_data_o : out std_ulogic_vector(7 downto 0);
    conv_pixel_valid_o: out std_ulogic;
    conv_pixel_row_o  : out std_ulogic_vector(1 downto 0);
    conv_pixel_col_o  : out std_ulogic_vector(1 downto 0);
    conv_result_i     : in  std_ulogic_vector(31 downto 0);
    conv_result_valid_i: in std_ulogic;
    -- Activation engine interface --
    act_data_o        : out std_ulogic_vector(31 downto 0);
    act_valid_o       : out std_ulogic;
    act_data_i        : in  std_ulogic_vector(31 downto 0);
    act_valid_i       : in  std_ulogic;
    -- Pooling engine interface --
    pool_pixel_data_o : out std_ulogic_vector(7 downto 0);
    pool_pixel_valid_o: out std_ulogic;
    pool_start_o      : out std_ulogic;
    pool_done_i       : in  std_ulogic;
    pool_result_i     : in  std_ulogic_vector(7 downto 0);
    pool_result_valid_i: in std_ulogic;
    -- Memory interface (for reading input feature maps / weights) --
    mem_addr_o        : out std_ulogic_vector(31 downto 0);
    mem_rd_o          : out std_ulogic;
    mem_data_i        : in  std_ulogic_vector(31 downto 0);
    mem_valid_i       : in  std_ulogic;
    -- Output interface (write result feature maps) --
    out_data_o        : out std_ulogic_vector(31 downto 0);
    out_valid_o       : out std_ulogic;
    out_addr_o        : out std_ulogic_vector(31 downto 0)
  );
end cnn_controller;

architecture rtl of cnn_controller is

  -- Main FSM states
  type state_t is (
    IDLE,
    LOAD_WEIGHTS,
    LOAD_PATCH,
    WAIT_CONV,
    ACTIVATE,
    WAIT_ACT,
    POOL_COLLECT,
    WAIT_POOL,
    WRITE_OUTPUT,
    NEXT_POSITION,
    NEXT_CHANNEL,
    LAYER_DONE
  );
  signal state : state_t;

  -- Position tracking
  signal row_pos    : unsigned(7 downto 0);
  signal col_pos    : unsigned(7 downto 0);
  signal in_ch_pos  : unsigned(7 downto 0);
  signal out_ch_pos : unsigned(7 downto 0);
  signal layer_idx  : unsigned(3 downto 0);

  -- Kernel position for loading
  signal kr_pos     : unsigned(1 downto 0); -- kernel row 0..2
  signal kc_pos     : unsigned(1 downto 0); -- kernel col 0..2
  signal weight_idx : unsigned(3 downto 0);

  -- Output dimensions
  signal out_h, out_w : unsigned(7 downto 0);

  -- Performance counters
  signal cycle_count : unsigned(31 downto 0);
  signal ops_count   : unsigned(31 downto 0);

  -- Stride
  signal stride_val : unsigned(1 downto 0);

  -- Output write address tracking
  signal out_wr_addr : unsigned(31 downto 0);

begin

  stride_val  <= unsigned(cfg_stride_i);
  layer_idx_o <= std_ulogic_vector(layer_idx);

  -- Output dimensions calculation
  out_h <= unsigned(cfg_input_h_i) - 2 when cfg_padding_i = '0' else unsigned(cfg_input_h_i);
  out_w <= unsigned(cfg_input_w_i) - 2 when cfg_padding_i = '0' else unsigned(cfg_input_w_i);

  -- ============================================================
  -- Main Controller FSM
  -- ============================================================
  controller_fsm: process(rstn_i, clk_i)
    variable v_addr_tmp : unsigned(31 downto 0);
  begin
    if rstn_i = '0' then
      state               <= IDLE;
      busy_o              <= '0';
      done_o              <= '0';
      row_pos             <= (others => '0');
      col_pos             <= (others => '0');
      in_ch_pos           <= (others => '0');
      out_ch_pos          <= (others => '0');
      layer_idx           <= (others => '0');
      kr_pos              <= (others => '0');
      kc_pos              <= (others => '0');
      weight_idx          <= (others => '0');
      cycle_count         <= (others => '0');
      ops_count           <= (others => '0');
      out_wr_addr         <= (others => '0');
      conv_start_o        <= '0';
      conv_clear_accum_o  <= '0';
      conv_weight_valid_o <= '0';
      conv_pixel_valid_o  <= '0';
      act_valid_o         <= '0';
      pool_pixel_valid_o  <= '0';
      pool_start_o        <= '0';
      mem_rd_o            <= '0';
      out_valid_o         <= '0';
      conv_weight_data_o  <= (others => '0');
      conv_weight_addr_o  <= (others => '0');
      conv_pixel_data_o   <= (others => '0');
      conv_pixel_row_o    <= (others => '0');
      conv_pixel_col_o    <= (others => '0');
      act_data_o          <= (others => '0');
      pool_pixel_data_o   <= (others => '0');
      mem_addr_o          <= (others => '0');
      out_data_o          <= (others => '0');
      out_addr_o          <= (others => '0');
    elsif rising_edge(clk_i) then
      -- Default pulse signals
      conv_start_o        <= '0';
      conv_clear_accum_o  <= '0';
      conv_weight_valid_o <= '0';
      conv_pixel_valid_o  <= '0';
      act_valid_o         <= '0';
      pool_pixel_valid_o  <= '0';
      pool_start_o        <= '0';
      mem_rd_o            <= '0';
      out_valid_o         <= '0';
      done_o              <= '0';

      -- Performance counter (always counting when busy)
      if busy_o = '1' then
        cycle_count <= cycle_count + 1;
      end if;

      case state is
        -- ==============================
        when IDLE =>
          busy_o <= '0';
          if cfg_start_i = '1' then
            busy_o      <= '1';
            state       <= LOAD_WEIGHTS;
            row_pos     <= (others => '0');
            col_pos     <= (others => '0');
            in_ch_pos   <= (others => '0');
            out_ch_pos  <= (others => '0');
            weight_idx  <= (others => '0');
            cycle_count <= (others => '0');
            ops_count   <= (others => '0');
            out_wr_addr <= (others => '0');
            conv_clear_accum_o <= '1';
          end if;

        -- ==============================
        when LOAD_WEIGHTS =>
          -- Load 3×3 = 9 weights for current (out_ch, in_ch) pair
          -- Request weight from memory
          mem_rd_o   <= '1';
          -- Weight address: out_ch * 9 * in_ch_count + in_ch * 9 + weight_idx
          v_addr_tmp := resize(out_ch_pos * unsigned(cfg_input_ch_i), 32);
          v_addr_tmp := resize(v_addr_tmp(15 downto 0) * to_unsigned(9, 4), 32);
          v_addr_tmp := v_addr_tmp + resize(in_ch_pos * to_unsigned(9, 4), 32);
          v_addr_tmp := v_addr_tmp + resize(weight_idx, 32);
          mem_addr_o <= std_ulogic_vector(v_addr_tmp);

          if mem_valid_i = '1' then
            conv_weight_data_o  <= mem_data_i(7 downto 0);
            conv_weight_addr_o  <= std_ulogic_vector(weight_idx);
            conv_weight_valid_o <= '1';
            if weight_idx = to_unsigned(8, 4) then
              weight_idx <= (others => '0');
              state      <= LOAD_PATCH;
              kr_pos     <= (others => '0');
              kc_pos     <= (others => '0');
            else
              weight_idx <= weight_idx + 1;
            end if;
          end if;

        -- ==============================
        when LOAD_PATCH =>
          -- Load 3×3 input patch at current position
          mem_rd_o   <= '1';
          -- Pixel address: in_ch * H * W + (row + kr) * W + col + kc
          v_addr_tmp := resize(in_ch_pos * unsigned(cfg_input_h_i), 32);
          v_addr_tmp := resize(v_addr_tmp(15 downto 0) * unsigned(cfg_input_w_i), 32);
          v_addr_tmp := v_addr_tmp + resize((row_pos + resize(kr_pos, 8)) * unsigned(cfg_input_w_i), 32);
          v_addr_tmp := v_addr_tmp + resize(col_pos, 32) + resize(kc_pos, 32);
          mem_addr_o <= std_ulogic_vector(v_addr_tmp);

          if mem_valid_i = '1' then
            conv_pixel_data_o  <= mem_data_i(7 downto 0);
            conv_pixel_row_o   <= std_ulogic_vector(kr_pos);
            conv_pixel_col_o   <= std_ulogic_vector(kc_pos);
            conv_pixel_valid_o <= '1';

            if kc_pos = to_unsigned(2, 2) then
              kc_pos <= (others => '0');
              if kr_pos = to_unsigned(2, 2) then
                kr_pos     <= (others => '0');
                conv_start_o <= '1';
                state      <= WAIT_CONV;
              else
                kr_pos <= kr_pos + 1;
              end if;
            else
              kc_pos <= kc_pos + 1;
            end if;
          end if;

        -- ==============================
        when WAIT_CONV =>
          if conv_result_valid_i = '1' then
            -- Track operations: 9 MACs = 18 ops per convolution
            ops_count <= ops_count + 18;
            -- Check if more input channels to accumulate
            if in_ch_pos < unsigned(cfg_input_ch_i) - 1 then
              in_ch_pos  <= in_ch_pos + 1;
              state      <= LOAD_WEIGHTS;
            else
              -- All input channels done, apply activation
              in_ch_pos  <= (others => '0');
              state      <= ACTIVATE;
            end if;
          end if;

        -- ==============================
        when ACTIVATE =>
          act_data_o  <= conv_result_i;
          act_valid_o <= '1';
          state       <= WAIT_ACT;

        -- ==============================
        when WAIT_ACT =>
          if act_valid_i = '1' then
            if cfg_pool_en_i = '1' then
              -- Feed to pooling engine
              pool_pixel_data_o  <= act_data_i(7 downto 0);
              pool_pixel_valid_o <= '1';
              state              <= POOL_COLLECT;
            else
              -- Direct output
              state <= WRITE_OUTPUT;
            end if;
          end if;

        -- ==============================
        when POOL_COLLECT =>
          if pool_done_i = '1' then
            state <= WRITE_OUTPUT;
          end if;

        -- ==============================
        when WAIT_POOL =>
          if pool_result_valid_i = '1' then
            state <= WRITE_OUTPUT;
          end if;

        -- ==============================
        when WRITE_OUTPUT =>
          if cfg_pool_en_i = '1' then
            out_data_o <= x"000000" & pool_result_i;
          else
            out_data_o <= act_data_i;
          end if;
          out_addr_o  <= std_ulogic_vector(out_wr_addr);
          out_valid_o <= '1';
          out_wr_addr <= out_wr_addr + 1;
          conv_clear_accum_o <= '1'; -- clear accumulator for next position
          state <= NEXT_POSITION;

        -- ==============================
        when NEXT_POSITION =>
          -- Move sliding window
          if col_pos + resize(stride_val, 8) + 2 < unsigned(cfg_input_w_i) then
            col_pos <= col_pos + resize(stride_val, 8);
            state   <= LOAD_WEIGHTS;
          else
            col_pos <= (others => '0');
            if row_pos + resize(stride_val, 8) + 2 < unsigned(cfg_input_h_i) then
              row_pos <= row_pos + resize(stride_val, 8);
              state   <= LOAD_WEIGHTS;
            else
              row_pos <= (others => '0');
              state   <= NEXT_CHANNEL;
            end if;
          end if;

        -- ==============================
        when NEXT_CHANNEL =>
          if out_ch_pos < unsigned(cfg_output_ch_i) - 1 then
            out_ch_pos <= out_ch_pos + 1;
            state      <= LOAD_WEIGHTS;
          else
            out_ch_pos <= (others => '0');
            state      <= LAYER_DONE;
          end if;

        -- ==============================
        when LAYER_DONE =>
          done_o    <= '1';
          busy_o    <= '0';
          layer_idx <= layer_idx + 1;
          state     <= IDLE;

        when others =>
          state <= IDLE;
      end case;
    end if;
  end process controller_fsm;

  perf_cycles_o <= std_ulogic_vector(cycle_count);
  perf_ops_o    <= std_ulogic_vector(ops_count);

end rtl;
