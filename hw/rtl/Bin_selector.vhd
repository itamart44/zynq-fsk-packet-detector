


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity Bin_selector is
   generic (   windows : integer := 256; 
            sample_size : integer := 16 );
    Port ( clk, reset : in STD_LOGIC;
             bin_k      : in integer range 0 to windows -1 ;
           fft_real_out : in STD_LOGIC_vector ( (sample_size -1) downto 0);
           fft_imeg_out : in STD_LOGIC_vector ((sample_size -1) downto 0);
           fft_output_valid : in STD_LOGIC;
           bin0_real : out signed ((sample_size -1) downto 0);
           bin0_imeg : out signed ((sample_size -1) downto 0);
           bin1_real : out signed ((sample_size -1) downto 0);
           bin1_imeg : out signed ((sample_size -1) downto 0);
           bins_valid : out STD_LOGIC);
end Bin_selector;

architecture Behavioral of Bin_selector is
constant Fs : integer := 1000000;
constant F1 : integer := 100000;
constant F2 : integer := 120000;
constant BIN_F1 : integer := (F1 * windows) / Fs;
constant BIN_F2 : integer := (F2 * windows) / Fs;
signal bin0_seen : std_logic := '0';
signal bin1_seen : std_logic := '0';
begin
process(clk)
begin
if rising_edge(clk) then
    if reset = '1' then
        bin0_real <= (others => '0');
        bin0_imeg <= (others => '0');
        bin1_real <= (others => '0');
        bin1_imeg <= (others => '0');
        bin0_seen <= '0';
        bin1_seen <= '0';
        bins_valid <= '0';
    else
        bins_valid <= '0';
        if fft_output_valid = '1' then
            if bin_k = BIN_F1 then
                bin0_real <= signed(fft_real_out);
                bin0_imeg <= signed(fft_imeg_out);
                bin0_seen <= '1';
            end if;
            if bin_k = BIN_F2 then
                bin1_real <= signed(fft_real_out);
                bin1_imeg <= signed(fft_imeg_out);
                bin1_seen <= '1';
            end if;
            if ( (bin_k = BIN_F1 and bin1_seen = '1') or
                 (bin_k = BIN_F2 and bin0_seen = '1') ) then
                bins_valid <= '1';
                bin0_seen <= '0';
                bin1_seen <= '0';
            end if;
        end if;
    end if;
end if;
end process;
end Behavioral;
