-- Driver for WS2812 - 16 RGB LED RING
-- Steven J. Merrifield, 14 Jan 2017
-- http://stevenmerrifield.com

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity WS2812 is
	generic (
		clock_frequency : integer := 50_000_000 -- Hertz
	);
	port (
		clk : in std_logic;
		data : out std_logic_vector(23 downto 0); -- for testbench validation only
		serial : out std_logic
	);
end entity WS2812;

architecture arch of WS2812 is
--	constant T0H : integer := (350 * clock_frequency) / 1_000_000_000; 
--	constant T0L : integer := (800 * clock_frequency) / 1_000_000_000;
--	constant T1H : integer := (700 * clock_frequency) / 1_000_000_000;
--	constant T1L : integer := (600 * clock_frequency) / 1_000_000_000;
--	constant RES : integer := (50000 * clock_frequency) / 1_000_000_000;

	constant T0H : integer := 17;
	constant T0L : integer := 38; -- compensate for state changes
	constant T1H : integer := 35;
	constant T1L : integer := 28; -- compensate for state changes
	constant RES : integer := 2500;
	
	type LED_ring is array (0 to 15) of std_logic_vector(23 downto 0);
	type state_machine is (load, sending, send_bit, reset);

begin
	process
		variable state : state_machine := load;
		variable GRB : std_logic_vector(23 downto 0) := x"000000";
		variable delay_high_counter : integer := 0;
		variable delay_low_counter : integer := 0;
		variable index : integer := 0;
		variable bit_counter : integer := 0;
		variable LED : LED_ring := (x"FF0000", -- LED 0, Green Red Blue
											x"00FF00", -- LED 1
											x"0000FF", -- LED 2
											x"FFFFFF", -- LED 3
											x"330000", -- LED 4
											x"003300", -- LED 5
											x"000033", -- LED 6
											x"660000", -- LED 7
											x"006600", -- LED 8
											x"000066", -- LED 9
											x"AA0000", -- LED 10
											x"00AA00", -- LED 11
											x"0000AA", -- LED 12
											x"333333", -- LED 13
											x"666666", -- LED 14
											x"AAAAAA"); -- LED 15

	begin
		wait until rising_edge(clk);
		data <= GRB; -- temporary testing only
	
		case state is
			when load =>
						GRB := LED(index);
						bit_counter := 24;
						state := sending;
			when sending =>
					if (bit_counter > 0) then
						bit_counter := bit_counter - 1;
						if GRB(bit_counter) = '1' then
							delay_high_counter := T1H;
							delay_low_counter := T1L;
						else
							delay_high_counter := T0H;
							delay_low_counter := T0L;
						end if;
						state := send_bit;
					else
						if (index < 15) then
							index := index + 1;
							state := load;
						else
							delay_low_counter := RES;
							state := reset;
						end if;
					end if;
			when send_bit =>
					if (delay_high_counter > 0) then
						serial <= '1';
						delay_high_counter := delay_high_counter - 1;
					elsif (delay_low_counter > 0) then
							serial <= '0';
							delay_low_counter := delay_low_counter - 1;
					else
						state := sending;
					end if;
			when reset =>
					if (delay_low_counter > 0) then
						serial <= '0';
						delay_low_counter := delay_low_counter - 1;
					else
						index := 0;
						--state := possibly load new data for next cycle
					end if;
			when others => null;
		end case;
	end process;
end arch;
