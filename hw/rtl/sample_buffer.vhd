library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sample_buffer is
    generic (
        windows : integer := 256;
        sample_size : integer := 16
    );
    Port (
        clk, reset : in STD_LOGIC;
        fft_read_done : in STD_LOGIC;
        sample_in : in signed((sample_size-1) downto 0);
        sample_valid : in STD_LOGIC;
        energy_detected, energy_valid : in STD_LOGIC;
        read_addr : in integer range 0 to windows-1;
        read_data : out signed((sample_size-1) downto 0);
        buffer_full : out STD_LOGIC
    );
end sample_buffer;

architecture Behavioral of sample_buffer is

signal write_index : integer range 0 to windows-1 := 0;

type bufferType is array (0 to windows-1) of signed((sample_size-1) downto 0);
signal bufferstat : bufferType;

signal buffer_full_reg : std_logic := '0';

begin

process(clk)
begin
if rising_edge(clk) then

    if reset = '1' then
        write_index <= 0;
        buffer_full_reg <= '0';

    else

        if fft_read_done = '1' then
            write_index <= 0;
            buffer_full_reg <= '0';

        elsif sample_valid = '1' and buffer_full_reg = '0' then

            bufferstat(write_index) <= sample_in;

            if write_index = windows-1 then
                buffer_full_reg <= '1';
            else
                write_index <= write_index + 1;
            end if;

        elsif buffer_full_reg = '1' then

            if energy_valid = '1' then
                if energy_detected = '0' then
                    write_index <= 0;
                    buffer_full_reg <= '0';
                end if;
            end if;

        end if;

    end if;

end if;
end process;

read_data <= bufferstat(read_addr);
buffer_full <= buffer_full_reg;

end Behavioral;
