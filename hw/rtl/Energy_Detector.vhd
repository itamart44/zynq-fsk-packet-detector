library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Energy_Detector is
generic ( WINDOW_SIZE : integer := 256;
          MIN_ENERGY : unsigned(39 downto 0) := to_unsigned(1000000000,40);
          sample_size : integer := 16 ); 
    Port (
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        sample_in : in signed((sample_size-1) downto 0);
        sample_valid : in STD_LOGIC;
        energy_detected : out STD_LOGIC;
        energy_valid : out STD_LOGIC
    );
end Energy_Detector;

architecture Behavioral of Energy_Detector is
signal energy_sum : unsigned(39 downto 0) := (others => '0');
signal sample_counter : integer range 0 to WINDOW_SIZE := 0;
signal detected_reg : STD_LOGIC := '0';
signal valid_reg : STD_LOGIC := '0';
begin
process(clk)
variable sample_sq : unsigned(31 downto 0);
begin
    if rising_edge(clk) then
        if reset = '1' then
            energy_sum <= (others => '0');
            sample_counter <= 0;
            detected_reg <= '0';
            valid_reg <= '0';
        else
            if sample_valid = '1' then

            sample_sq := unsigned(sample_in * sample_in);

             if sample_counter = WINDOW_SIZE-1 then

                if (energy_sum + resize(sample_sq,40)) > MIN_ENERGY then
                     detected_reg <= '1';
                 else
                 detected_reg <= '0';
                  end if;

        valid_reg <= '1';
        energy_sum <= (others => '0');
        sample_counter <= 0;

    else

        energy_sum <= energy_sum + resize(sample_sq,40);
        sample_counter <= sample_counter + 1;
        valid_reg <= '0';

    end if;

end if;
        end if;
    end if;
end process;
energy_detected <= detected_reg;
energy_valid <= valid_reg;
end Behavioral;
