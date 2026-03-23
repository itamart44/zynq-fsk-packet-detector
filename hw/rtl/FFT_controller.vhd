library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FFT_controller is
generic(
    windows : integer := 256;
    sample_size : integer := 16
);
port(
    clk : in std_logic;
    reset : in std_logic;

    buffer_ready : in std_logic;

    read_data : in signed(sample_size-1 downto 0);
    read_addr : out integer range 0 to windows-1;

    fft_ready : in std_logic;

    fft_data_in : out signed(sample_size-1 downto 0);
    fft_valid : out std_logic;
    fft_last  : out std_logic;

    fft_data_ready : out std_logic
);
end FFT_controller;

architecture Behavioral of FFT_controller is

signal index : integer range 0 to windows-1 := 0;
signal sending : std_logic := '0';

begin

process(clk)
begin
if rising_edge(clk) then

    if reset='1' then
        sending <= '0';
        index <= 0;
        fft_valid <= '0';
        fft_last <= '0';
        fft_data_ready <= '0';

    else

        fft_last <= '0';
        fft_data_ready <= '0';
        fft_valid <= '0';

        if sending='0' then

            if buffer_ready='1' then
                sending <= '1';
                index <= 0;
            end if;

        else

            if fft_ready='1' then

                fft_valid <= '1';

                if index = windows-1 then
                    fft_last <= '1';
                    sending <= '0';
                    fft_data_ready <= '1';
                else
                    index <= index + 1;
                end if;

            end if;

        end if;
    end if;
        end if;
end process;

read_addr <= index;
fft_data_in <= read_data;

end Behavioral;
