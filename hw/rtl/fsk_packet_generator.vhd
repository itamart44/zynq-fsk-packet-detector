-- fsk_packet_generator.vhd
--
-- Internal FSK packet source for self-testing the detection pipeline.
-- Replaces the external sample_in / sample_valid board ports so the
-- design can be verified without an ADC or signal generator attached.
--
-- Packet structure (matches Sync_Detector + Adders_Extractor):
--   PREAMBLE_BITS × 120 kHz (bit=0) — primes the energy detector and
--     aligns the sample_buffer windows to bit boundaries
--   SYNC_WORD (16 bits, MSB first, "1100010111011000")
--   ADDRESS   (ADDR_LENGTH=7 bits, LSB first)
--
-- FSK mapping confirmed from FSK_Decision.vhd (power0 > power1 → bit='1'):
--   bit = 1  →  100 kHz  (F1, bin 25)
--   bit = 0  →  120 kHz  (F2, bin 30)
--
-- DDS uses a 16-bit phase accumulator and a 256-entry sine ROM (amplitude 8000).
-- Phase increments at Fs = 1 MHz (CLK_DIV=100 on a 100 MHz clock):
--   100 kHz: round(65536 × 100000 / 1000000) = 6554
--   120 kHz: round(65536 × 120000 / 1000000) = 7864
--
-- Between packets the generator outputs LFSR noise scaled to NOISE_AMPLITUDE
-- (default 200 counts), keeping signal energy well below MIN_ENERGY=1e9 so
-- the energy detector stays idle during gaps.
--
-- Address matching:
--   All channels' address LFSRs share the same seed, so packet 1 transmits
--   an identical address on every channel (fires match_detected once near
--   the start). Channel 0 and channels 1..N-1 use different LFSR feedback
--   taps, so from packet 2 onward each channel's address sequence diverges.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fsk_packet_generator is
    generic (
        N_CHANNEL       : integer := 2;    -- must match multi_channel_top N_channel
        SAMPLE_SIZE     : integer := 16;
        SAMPLES_PER_BIT : integer := 256;  -- = FFT window size
        SYNC_LENGTH     : integer := 16;
        ADDR_LENGTH     : integer := 7;
        CLK_DIV         : integer := 100;  -- 100 MHz clk / 1 MHz sample rate
        NOISE_AMPLITUDE : integer := 200;  -- peak noise counts (< energy threshold)
        PREAMBLE_BITS   : integer := 4;    -- 120 kHz windows before sync
        GAP_BITS        : integer := 2     -- noise windows between packets
    );
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        -- Packed output: ch[i] occupies bits [(i+1)*SAMPLE_SIZE-1 : i*SAMPLE_SIZE]
        sample_out   : out std_logic_vector(N_CHANNEL * SAMPLE_SIZE - 1 downto 0);
        -- One valid strobe per channel, all asserted together (channels are synchronous)
        sample_valid : out std_logic_vector(N_CHANNEL - 1 downto 0)
    );
end fsk_packet_generator;

architecture Behavioral of fsk_packet_generator is

    -- ── Sine ROM ─────────────────────────────────────────────────────────────
    -- 256-point, amplitude 8000.  Top 8 bits of 16-bit phase accumulator index.
    -- Energy per 256-sample window ≈ 128 × 8000² ≈ 8.2 × 10⁹ >> MIN_ENERGY=1e9.
    type sine_lut_t is array (0 to 255) of integer range -8000 to 8000;
    constant SINE_LUT : sine_lut_t := (
    --   +0     +1     +2     +3     +4     +5     +6     +7
         0,    196,   393,   589,   784,   979,  1174,  1368,  -- 0
      1561,   1753,  1944,  2134,  2322,  2509,  2695,  2879,  -- 8
      3061,   3242,  3420,  3597,  3771,  3943,  4113,  4280,  -- 16
      4445,   4606,  4766,  4922,  5075,  5225,  5372,  5516,  -- 24
      5657,   5794,  5928,  6058,  6184,  6307,  6426,  6541,  -- 32
      6652,   6759,  6862,  6961,  7055,  7146,  7232,  7314,  -- 40
      7391,   7464,  7532,  7596,  7656,  7710,  7760,  7806,  -- 48
      7846,   7882,  7913,  7940,  7961,  7978,  7990,  7998,  -- 56
      8000,   7998,  7990,  7978,  7961,  7940,  7913,  7882,  -- 64
      7846,   7806,  7760,  7710,  7656,  7596,  7532,  7464,  -- 72
      7391,   7314,  7232,  7146,  7055,  6961,  6862,  6759,  -- 80
      6652,   6541,  6426,  6307,  6184,  6058,  5928,  5794,  -- 88
      5657,   5516,  5372,  5225,  5075,  4922,  4766,  4606,  -- 96
      4445,   4280,  4113,  3943,  3771,  3597,  3420,  3242,  -- 104
      3061,   2879,  2695,  2509,  2322,  2134,  1944,  1753,  -- 112
      1561,   1368,  1174,   979,   784,   589,   393,   196,  -- 120
         0,   -196,  -393,  -589,  -784,  -979, -1174, -1368,  -- 128
     -1561,  -1753, -1944, -2134, -2322, -2509, -2695, -2879,  -- 136
     -3061,  -3242, -3420, -3597, -3771, -3943, -4113, -4280,  -- 144
     -4445,  -4606, -4766, -4922, -5075, -5225, -5372, -5516,  -- 152
     -5657,  -5794, -5928, -6058, -6184, -6307, -6426, -6541,  -- 160
     -6652,  -6759, -6862, -6961, -7055, -7146, -7232, -7314,  -- 168
     -7391,  -7464, -7532, -7596, -7656, -7710, -7760, -7806,  -- 176
     -7846,  -7882, -7913, -7940, -7961, -7978, -7990, -7998,  -- 184
     -8000,  -7998, -7990, -7978, -7961, -7940, -7913, -7882,  -- 192
     -7846,  -7806, -7760, -7710, -7656, -7596, -7532, -7464,  -- 200
     -7391,  -7314, -7232, -7146, -7055, -6961, -6862, -6759,  -- 208
     -6652,  -6541, -6426, -6307, -6184, -6058, -5928, -5794,  -- 216
     -5657,  -5516, -5372, -5225, -5075, -4922, -4766, -4606,  -- 224
     -4445,  -4280, -4113, -3943, -3771, -3597, -3420, -3242,  -- 232
     -3061,  -2879, -2695, -2509, -2322, -2134, -1944, -1753,  -- 240
     -1561,  -1368, -1174,  -979,  -784,  -589,  -393,  -196   -- 248
    );

    -- ── DDS increments ────────────────────────────────────────────────────────
    -- 16-bit accumulator; top 8 bits select the sine LUT entry.
    -- bit=1 → 100 kHz: floor(65536 × 100000 / 1000000) rounded → 6554
    -- bit=0 → 120 kHz: floor(65536 × 120000 / 1000000) rounded → 7864
    constant PHASE_INC_BIT1 : unsigned(15 downto 0) := to_unsigned(6554, 16);
    constant PHASE_INC_BIT0 : unsigned(15 downto 0) := to_unsigned(7864, 16);

    -- ── Sync word ─────────────────────────────────────────────────────────────
    -- Transmitted MSB-first (bit 15 enters the shift register first).
    -- Sync_Detector shifts: next = reg(14:0) & bit_in, matches when next = SYNC.
    constant SYNC_WORD : std_logic_vector(SYNC_LENGTH - 1 downto 0) := "1100010111011000";

    constant PKT_BITS : integer := SYNC_LENGTH + ADDR_LENGTH;  -- 23

    -- ── State machine ─────────────────────────────────────────────────────────
    type state_t is (ST_GAP, ST_PREAMBLE, ST_PACKET);

    -- ── Per-channel array types ───────────────────────────────────────────────
    type phase_arr_t  is array (0 to N_CHANNEL - 1) of unsigned(15 downto 0);
    type lfsr_arr_t   is array (0 to N_CHANNEL - 1) of std_logic_vector(7 downto 0);
    type addr_arr_t   is array (0 to N_CHANNEL - 1) of std_logic_vector(ADDR_LENGTH - 1 downto 0);
    type sample_arr_t is array (0 to N_CHANNEL - 1) of signed(SAMPLE_SIZE - 1 downto 0);

    -- ── Signals ───────────────────────────────────────────────────────────────
    signal state      : state_t := ST_GAP;
    signal clk_cnt    : integer range 0 to CLK_DIV - 1 := 0;
    signal tick       : std_logic := '0';  -- 1-cycle pulse every CLK_DIV clocks

    -- beat_cnt counts samples within one bit period
    signal beat_cnt   : integer range 0 to SAMPLES_PER_BIT - 1 := 0;
    -- bit_idx counts bits within a packet (sync + address)
    signal bit_idx    : integer range 0 to PKT_BITS - 1 := 0;
    -- period_cnt counts bit windows within the gap or preamble phase
    signal period_cnt : integer range 0 to 255 := 0;

    signal phase_acc  : phase_arr_t  := (others => (others => '0'));
    signal addr_lfsr  : lfsr_arr_t;   -- random address source per channel
    signal noise_lfsr : lfsr_arr_t;   -- independent noise source per channel
    signal ch_addr    : addr_arr_t    := (others => (others => '0'));
    signal ch_sample  : sample_arr_t  := (others => (others => '0'));

begin

    -- ── Clock divider ─────────────────────────────────────────────────────────
    -- Generates one sample_valid pulse every CLK_DIV clock cycles.
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                clk_cnt <= 0;
                tick    <= '0';
            elsif clk_cnt = CLK_DIV - 1 then
                clk_cnt <= 0;
                tick    <= '1';
            else
                clk_cnt <= clk_cnt + 1;
                tick    <= '0';
            end if;
        end if;
    end process;

    -- ── Main generator ────────────────────────────────────────────────────────
    process(clk)
        -- LFSR step variables (Galois form, poly x^8+x^6+x^5+x^4+1)
        variable lv       : std_logic_vector(7 downto 0);
        variable fb       : std_logic;
        -- Per-sample computation
        variable bit_val  : std_logic;
        variable inc      : unsigned(15 downto 0);
        variable lut_idx  : integer range 0 to 255;
        variable nval     : integer;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state      <= ST_GAP;
                beat_cnt   <= 0;
                bit_idx    <= 0;
                period_cnt <= 0;
                for i in 0 to N_CHANNEL - 1 loop
                    -- Staggered initial phases avoid identical outputs at t=0
                    phase_acc(i)  <= to_unsigned(i * 8192, 16);
                    -- Non-zero seeds so LFSRs never lock up
                    addr_lfsr(i)  <= std_logic_vector(to_unsigned(1, 8));
                    noise_lfsr(i) <= std_logic_vector(to_unsigned(i * 37 + 5, 8));
                    ch_addr(i)    <= (others => '0');
                    ch_sample(i)  <= (others => '0');
                end loop;
                sample_valid <= (others => '0');

            elsif tick = '1' then
                -- sample_valid is high for this one clock cycle only
                sample_valid <= (others => '1');

                case state is

                    -- ── GAP: low-energy LFSR noise ───────────────────────────
                    when ST_GAP =>
                        for i in 0 to N_CHANNEL - 1 loop
                            lv := noise_lfsr(i);
                            fb := lv(7) xor lv(5) xor lv(4) xor lv(3);
                            noise_lfsr(i) <= lv(6 downto 0) & fb;
                            -- Scale 8-bit signed LFSR value to NOISE_AMPLITUDE
                            nval := to_integer(signed(lv)) * NOISE_AMPLITUDE / 128;
                            ch_sample(i) <= to_signed(nval, SAMPLE_SIZE);
                        end loop;

                        if beat_cnt = SAMPLES_PER_BIT - 1 then
                            beat_cnt <= 0;
                            if period_cnt = GAP_BITS - 1 then
                                period_cnt <= 0;

                                -- Advance all address LFSRs and latch new addresses.
                                -- All channels share the same seed (see reset block),
                                -- so packet 1 transmits the same address on every
                                -- channel. Channel 0 uses a different feedback tap
                                -- than channels 1..N-1, so their sequences diverge
                                -- from packet 2 onward.
                                for i in 0 to N_CHANNEL - 1 loop
                                    lv := addr_lfsr(i);
                                    if i = 0 then
                                        fb := lv(7) xor lv(5) xor lv(4) xor lv(3);
                                    else
                                        fb := lv(7) xor lv(6) xor lv(5) xor lv(4);
                                    end if;
                                    addr_lfsr(i) <= lv(6 downto 0) & fb;
                                    ch_addr(i)   <= lv(ADDR_LENGTH - 1 downto 0);
                                end loop;

                                -- Zero phases for a clean tone start
                                for i in 0 to N_CHANNEL - 1 loop
                                    phase_acc(i) <= (others => '0');
                                end loop;
                                state <= ST_PREAMBLE;
                            else
                                period_cnt <= period_cnt + 1;
                            end if;
                        else
                            beat_cnt <= beat_cnt + 1;
                        end if;

                    -- ── PREAMBLE: constant 120 kHz tone ──────────────────────
                    -- All-zero bits (120 kHz) prime the energy detector and
                    -- align the sample_buffer windows to subsequent bit boundaries.
                    when ST_PREAMBLE =>
                        for i in 0 to N_CHANNEL - 1 loop
                            -- Use current phase BEFORE advancing (standard DDS)
                            lut_idx := to_integer(phase_acc(i)(15 downto 8));
                            ch_sample(i) <= to_signed(SINE_LUT(lut_idx), SAMPLE_SIZE);
                            phase_acc(i) <= phase_acc(i) + PHASE_INC_BIT0;
                        end loop;

                        if beat_cnt = SAMPLES_PER_BIT - 1 then
                            beat_cnt <= 0;
                            if period_cnt = PREAMBLE_BITS - 1 then
                                period_cnt <= 0;
                                bit_idx    <= 0;
                                -- Reset phases so each packet's sync starts phase-coherent
                                for i in 0 to N_CHANNEL - 1 loop
                                    phase_acc(i) <= (others => '0');
                                end loop;
                                state <= ST_PACKET;
                            else
                                period_cnt <= period_cnt + 1;
                            end if;
                        else
                            beat_cnt <= beat_cnt + 1;
                        end if;

                    -- ── PACKET: sync word (MSB first) then address (LSB first) ─
                    when ST_PACKET =>
                        for i in 0 to N_CHANNEL - 1 loop
                            if bit_idx < SYNC_LENGTH then
                                -- Sync: bit SYNC_LENGTH-1-bit_idx is transmitted first
                                bit_val := SYNC_WORD(SYNC_LENGTH - 1 - bit_idx);
                            else
                                -- Address: bit 0 (LSB) is transmitted first
                                bit_val := ch_addr(i)(bit_idx - SYNC_LENGTH);
                            end if;

                            if bit_val = '1' then
                                inc := PHASE_INC_BIT1;   -- 100 kHz → power0 dominant
                            else
                                inc := PHASE_INC_BIT0;   -- 120 kHz → power1 dominant
                            end if;

                            lut_idx := to_integer(phase_acc(i)(15 downto 8));
                            ch_sample(i) <= to_signed(SINE_LUT(lut_idx), SAMPLE_SIZE);
                            phase_acc(i) <= phase_acc(i) + inc;
                        end loop;

                        if beat_cnt = SAMPLES_PER_BIT - 1 then
                            beat_cnt <= 0;
                            if bit_idx = PKT_BITS - 1 then
                                bit_idx    <= 0;
                                period_cnt <= 0;
                                state      <= ST_GAP;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            beat_cnt <= beat_cnt + 1;
                        end if;

                end case;

            else
                sample_valid <= (others => '0');
            end if;
        end if;
    end process;

    -- ── Output packing ────────────────────────────────────────────────────────
    -- ch0 → bits [SAMPLE_SIZE-1:0], ch1 → bits [2*SAMPLE_SIZE-1:SAMPLE_SIZE], etc.
    -- Matches multi_channel_top convention: sample_in[31:16]=ch1, [15:0]=ch0.
    gen_pack : for i in 0 to N_CHANNEL - 1 generate
        sample_out((i + 1) * SAMPLE_SIZE - 1 downto i * SAMPLE_SIZE) <=
            std_logic_vector(ch_sample(i));
    end generate gen_pack;

end Behavioral;
