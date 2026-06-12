library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity channel_matcher is
generic (
    N_channel  : integer := 2;
    ADDR_WIDTH : integer := 7
);
port (
    clk, reset     : in  std_logic;
    adders_out     : in  std_logic_vector(N_channel*ADDR_WIDTH-1 downto 0);
    adders_valid   : in  std_logic_vector(N_channel-1 downto 0);
    match_detected : out std_logic
);
end channel_matcher;

architecture Behavioral of channel_matcher is

type addr_array is array (0 to N_channel-1) of std_logic_vector(ADDR_WIDTH-1 downto 0);

signal addr_in    : addr_array;
signal addr_latch : addr_array;
signal latch_valid : std_logic_vector(N_channel-1 downto 0);

begin

-- Combinational unpack of the flat input bus
gen_unpack : for i in 0 to N_channel-1 generate
    addr_in(i) <= adders_out((i+1)*ADDR_WIDTH-1 downto i*ADDR_WIDTH);
end generate;

-- On each new address arrival, compare against all previously latched
-- addresses. match_detected is sticky: stays '1' once a match is found.
process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            match_detected <= '0';
            latch_valid    <= (others => '0');
            for i in 0 to N_channel-1 loop
                addr_latch(i) <= (others => '0');
            end loop;
        else
            for i in 0 to N_channel-1 loop
                if adders_valid(i) = '1' then
                    -- Compare this incoming address against every already-latched channel
                    for j in 0 to N_channel-1 loop
                        if j /= i and latch_valid(j) = '1' then
                            if addr_in(i) = addr_latch(j) then
                                match_detected <= '1';
                            end if;
                        end if;
                    end loop;
                    -- Latch for future comparisons
                    addr_latch(i)  <= addr_in(i);
                    latch_valid(i) <= '1';
                end if;
            end loop;
        end if;
    end if;
end process;

end Behavioral;
