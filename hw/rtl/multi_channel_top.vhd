library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity multi_channel_top is
generic (
    N_channel   : integer := 2;
    sample_size : integer := 16
);
port (
    clk, reset : in STD_LOGIC;

    sample_in    : in  std_logic_vector(N_channel*sample_size-1 downto 0);
    sample_valid : in  std_logic_vector(N_channel-1 downto 0);

    -- AXI GPIO control inputs (driven by axi_gpio_ctrl/thresh/freq)
    n_active   : in  std_logic_vector(3 downto 0);
    min_energy : in  std_logic_vector(31 downto 0);
    bin_f0     : in  std_logic_vector(7 downto 0);
    bin_f1     : in  std_logic_vector(7 downto 0);

    tready : in  std_logic;
    tdata  : out std_logic_vector(63 downto 0);
    tvalid : out std_logic;
    tlast  : out std_logic
);
end multi_channel_top;

architecture Behavioral of multi_channel_top is

-- -------------------------------------------------------------------------
-- Types
-- -------------------------------------------------------------------------
type sample_array is array (0 to N_channel-1) of signed(sample_size-1 downto 0);
-- Raw per-channel AXI Stream tdata as produced by TOP (36 bits: tag + payload)
type tdata_raw_array is array (0 to N_channel-1) of std_logic_vector(35 downto 0);
-- Zero-extended to 56 bits (bits [55:36] are reserved/zero), ready to be
-- concatenated with the 8 bits of match/best_valid/best_channel/ch_index
-- in the output mux below.
type tdata_array  is array (0 to N_channel-1) of std_logic_vector(55 downto 0);
type tvalid_array is array (0 to N_channel-1) of std_logic;
type addr_array   is array (0 to N_channel-1) of std_logic_vector(6 downto 0);

-- -------------------------------------------------------------------------
-- Signals
-- -------------------------------------------------------------------------
signal sample_arr : sample_array;

signal tdata_raw : tdata_raw_array;
signal tdata_ch  : tdata_array;
signal tvalid_ch : tvalid_array;
signal tlast_ch  : std_logic_vector(N_channel-1 downto 0);

-- Per-channel tready: only the currently-selected channel sees the real
-- tready; all others are held at '0' so their output state machines do
-- not advance while they are not being forwarded downstream.
signal tready_ch : std_logic_vector(N_channel-1 downto 0);

-- Address extraction
signal addr_arr       : addr_array;
signal addr_valid_arr : std_logic_vector(N_channel-1 downto 0);
signal addr_flat      : std_logic_vector(N_channel*7-1 downto 0);

-- Power extraction (latched from the AXI Stream output of each channel)
signal power0_ch      : std_logic_vector(N_channel*32-1 downto 0);
signal power1_ch      : std_logic_vector(N_channel*32-1 downto 0);
signal power_valid_ch : std_logic_vector(N_channel-1 downto 0);

-- Match / selector outputs
signal match_detected : std_logic;
signal best_channel   : std_logic_vector(2 downto 0);
signal best_valid     : std_logic;

-- Output MUX state
signal ch_index : integer range 0 to N_channel-1 := 0;

-- Runtime channel count clamped to [1, N_channel].
-- A GPIO value of 0 or > N_channel falls back to N_channel (all channels).
signal n_active_int : integer range 1 to N_channel;

begin

-- =========================================================================
-- Runtime channel count: convert GPIO std_logic_vector to integer and clamp
-- =========================================================================
n_active_int <= N_channel when (to_integer(unsigned(n_active)) = 0 or
                                to_integer(unsigned(n_active)) > N_channel)
                else to_integer(unsigned(n_active));

-- =========================================================================
-- Input unpacking
-- =========================================================================
gen_unpack : for i in 0 to N_channel-1 generate
    sample_arr(i) <= signed(sample_in((i+1)*sample_size-1 downto i*sample_size));
end generate;

-- =========================================================================
-- Per-channel tready: steer downstream backpressure to the active channel
-- =========================================================================
gen_tready : for i in 0 to N_channel-1 generate
    tready_ch(i) <= tready when ch_index = i else '0';
end generate;

-- =========================================================================
-- Channel instances
-- min_energy, bin_f0, bin_f1 are broadcast to every channel instance.
-- =========================================================================
gen_channels : for i in 0 to N_channel-1 generate
    channel_inst : entity work.TOP
        port map (
            clk          => clk,
            reset        => reset,
            sample_in    => sample_arr(i),
            sample_valid => sample_valid(i),
            tready       => tready_ch(i),
            tdata        => tdata_raw(i),
            tvalid       => tvalid_ch(i),
            tlast        => tlast_ch(i),
            min_energy   => min_energy,
            bin_f0       => bin_f0,
            bin_f1       => bin_f1
        );
end generate;

-- =========================================================================
-- Zero-extend each channel's 36-bit tdata to 56 bits for the output mux
-- =========================================================================
gen_extend : for i in 0 to N_channel-1 generate
    tdata_ch(i) <= (55 downto 36 => '0') & tdata_raw(i);
end generate;

-- =========================================================================
-- Address extraction (combinational decode of the AXI Stream packets)
-- =========================================================================
gen_extract_addr : for i in 0 to N_channel-1 generate
    addr_arr(i)       <= tdata_raw(i)(6 downto 0);
    addr_valid_arr(i) <= '1' when (tvalid_ch(i) = '1' and
                                   tdata_raw(i)(35 downto 32) = "0100")
                         else '0';
end generate;

gen_flat : for i in 0 to N_channel-1 generate
    addr_flat((i+1)*7-1 downto i*7) <= addr_arr(i);
end generate;

-- =========================================================================
-- Power extraction (registered: latch power0/power1 as they stream out)
-- =========================================================================
gen_power : for i in 0 to N_channel-1 generate
    process(clk)
    begin
        if rising_edge(clk) then
            if tvalid_ch(i) = '1' then
                if tdata_raw(i)(35 downto 32) = "0001" then
                    power0_ch((i+1)*32-1 downto i*32) <= tdata_raw(i)(31 downto 0);
                elsif tdata_raw(i)(35 downto 32) = "0010" then
                    power1_ch((i+1)*32-1 downto i*32) <= tdata_raw(i)(31 downto 0);
                end if;
            end if;
        end if;
    end process;

    power_valid_ch(i) <= '1' when (tvalid_ch(i) = '1' and
                                   (tdata_raw(i)(35 downto 32) = "0001" or
                                    tdata_raw(i)(35 downto 32) = "0010"))
                         else '0';
end generate;

-- =========================================================================
-- Address matcher
-- =========================================================================
matcher_inst : entity work.channel_matcher
    generic map (N_channel => N_channel, ADDR_WIDTH => 7)
    port map (
        clk            => clk,
        reset          => reset,
        adders_out     => addr_flat,
        adders_valid   => addr_valid_arr,
        match_detected => match_detected
    );

-- =========================================================================
-- Best-channel selector
-- =========================================================================
selector_inst : entity work.channel_selector
    generic map (N_channel => N_channel)
    port map (
        clk          => clk,
        reset        => reset,
        power0_in    => power0_ch,
        power1_in    => power1_ch,
        power_valid  => power_valid_ch,
        best_channel => best_channel,
        best_valid   => best_valid
    );

-- =========================================================================
-- Output MUX
--
-- Output word format (64 bits):
--   [63]     match_detected  — a pair of channels saw the same address
--   [62]     best_valid      — best_channel is meaningful
--   [61:59]  best_channel    — channel with largest power margin
--   [58:56]  ch_index        — which channel this word came from
--   [55:36]  (zero)
--   [35:32]  type tag        — 0001=power0 0010=power1 0011=sync 0100=addr
--   [31:0]   payload
--
-- ch_index cycles through [0, n_active_int-1].
-- Channels with index >= n_active_int are instantiated but never selected,
-- so their tready_ch stays '0' and their output stream stalls harmlessly.
-- =========================================================================
process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            ch_index <= 0;
            tvalid   <= '0';
            tlast    <= '0';
            tdata    <= (others => '0');
        else
            if tvalid_ch(ch_index) = '1' then
                tdata  <= match_detected &
                          best_valid      &
                          best_channel    &
                          std_logic_vector(to_unsigned(ch_index, 3)) &
                          tdata_ch(ch_index)(55 downto 0);
                tvalid <= '1';
                tlast  <= tlast_ch(ch_index);

                -- Advance to next channel when current packet ends
                if tlast_ch(ch_index) = '1' and tready = '1' then
                    if ch_index >= n_active_int - 1 then
                        ch_index <= 0;
                    else
                        ch_index <= ch_index + 1;
                    end if;
                end if;

            else
                -- Current channel is idle: rotate immediately so a busy
                -- channel is not blocked behind a silent one.
                tvalid <= '0';
                tlast  <= '0';
                if ch_index >= n_active_int - 1 then
                    ch_index <= 0;
                else
                    ch_index <= ch_index + 1;
                end if;
            end if;
        end if;
    end if;
end process;

end Behavioral;
