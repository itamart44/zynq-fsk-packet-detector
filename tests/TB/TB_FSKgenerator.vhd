library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity TB_FSKgenerator is
end TB_FSKgenerator;

architecture Behavioral of TB_FSKgenerator is
signal clk : STD_LOGIC := '0';
signal reset : STD_LOGIC := '1';
signal sample_in : signed(15 downto 0) := (others => '0');
signal sample_valid : STD_LOGIC := '0';
constant Fs : real := 1.0e6;
begin
    clk <= not clk after 5 ns;

    process
        variable value : real;
        variable f : real := 90000.0;
        variable n : integer := 0;
    begin
        wait for 50 ns;
        reset <= '0';

        loop
            wait until rising_edge(clk);
            value := 10000.0 * sin(2.0 * math_pi * f * real(n) / Fs);
            sample_in <= to_signed(integer(value), 16);
            sample_valid <= '1';

            if n = 255 then
                n := 0;
                if f > 125000.0 then
                    f := 90000.0;
                else
                    f := f + 5000.0;
                end if;
            else
                n := n + 1;
            end if;
        end loop;
    end process;

    uut: entity work.TOP
    generic map (
        adders_length => 7,
        sample_size => 16,
        sync_length => 16,
        windows => 256
    )
    port map (
        clk => clk,
        reset => reset,
        sample_in => sample_in,
        sample_valid => sample_valid
    );

end Behavioral;
