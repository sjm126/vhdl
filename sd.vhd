-- VHDL SD card interface
-- by Steven J. Merrifield, June 2008

-- Reads and writes a single block of data, and also writes continuous data
-- Tested on Xilinx Spartan 3 hardware, using Transcend and SanDisk Ultra II cards
-- Read states are derived from the Apple II emulator by Stephen Edwards 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_controller is
port (
	cs : out std_logic;
	mosi : out std_logic;
	miso : in std_logic;
	sclk : out std_logic;

	rd : in std_logic;
	wr : in std_logic;
	dm_in : in std_logic;	-- data mode, 0 = write continuously, 1 = write single block
	reset : in std_logic;
	din : in std_logic_vector(7 downto 0);
	dout : out std_logic_vector(7 downto 0);
	clk : in std_logic	-- twice the SPI clk
);

end sd_controller;

architecture rtl of sd_controller is
type states is (
	RST,
	INIT,
	CMD0,
	CMD55,
	CMD41,
	POLL_CMD,
  
	IDLE,	-- wait for read or write pulse
	READ_BLOCK,
	READ_BLOCK_WAIT,
	READ_BLOCK_DATA,
	READ_BLOCK_CRC,
	SEND_CMD,
	RECEIVE_BYTE_WAIT,
	RECEIVE_BYTE,
	WRITE_BLOCK_CMD,
	WRITE_BLOCK_INIT,		-- initialise write command
	WRITE_BLOCK_DATA,		-- loop through all data bytes
	WRITE_BLOCK_BYTE,		-- send one byte
	WRITE_BLOCK_WAIT		-- wait until not busy
);


-- one start byte, plus 512 bytes of data, plus two FF end bytes (CRC)
constant WRITE_DATA_SIZE : integer := 515;


signal state, return_state : states;
signal sclk_sig : std_logic := '0';
signal cmd_out : std_logic_vector(55 downto 0);
signal recv_data : std_logic_vector(7 downto 0);
signal address : std_logic_vector(31 downto 0);
signal cmd_mode : std_logic := '1';
signal data_mode : std_logic := '1';
signal response_mode : std_logic := '1';
signal data_sig : std_logic_vector(7 downto 0) := x"00";

begin
  
	process(clk,reset)
		variable byte_counter : integer range 0 to WRITE_DATA_SIZE;
		variable bit_counter : integer range 0 to 160;
	begin
		data_mode <= dm_in;

		if rising_edge(clk) then
			if (reset='1') then
				state <= RST;
				sclk_sig <= '0';
			else
				case state is
				
				when RST =>
					sclk_sig <= '0';
					cmd_out <= (others => '1');
					address <= x"00000000";
					byte_counter := 0;
					cmd_mode <= '1'; -- 0=data, 1=command
					response_mode <= '1';	-- 0=data, 1=command
					bit_counter := 160;
					cs <= '1';
					state <= INIT;
				
				when INIT =>		-- CS=1, send 80 clocks, CS=0
					if (bit_counter = 0) then
						cs <= '0';
						state <= CMD0;
					else
						bit_counter := bit_counter - 1;
						sclk_sig <= not sclk_sig;
					end if;	
				
				when CMD0 =>
					cmd_out <= x"FF400000000095";
					bit_counter := 55;
					return_state <= CMD55;
					state <= SEND_CMD;

				when CMD55 =>
					cmd_out <= x"FF770000000001";	-- 55d OR 40h = 77h
					bit_counter := 55;
					return_state <= CMD41;
					state <= SEND_CMD;
				
				when CMD41 =>
					cmd_out <= x"FF690000000001";	-- 41d OR 40h = 69h
					bit_counter := 55;
					return_state <= POLL_CMD;
					state <= SEND_CMD;
			
				when POLL_CMD =>
					if (recv_data(0) = '0') then
						state <= IDLE;
					else
						state <= CMD55;
					end if;
        	
				when IDLE => 
					if (rd = '1') then
						state <= READ_BLOCK;
					elsif (wr='1') then
						state <= WRITE_BLOCK_CMD;
					else
						state <= IDLE;
					end if;
				
				when READ_BLOCK =>
					cmd_out <= x"FF" & x"51" & address & x"FF";
					bit_counter := 55;
					return_state <= READ_BLOCK_WAIT;
					state <= SEND_CMD;
				
				when READ_BLOCK_WAIT =>
					if (sclk_sig='1' and miso='0') then
						state <= READ_BLOCK_DATA;
						byte_counter := 511;
						bit_counter := 7;
						return_state <= READ_BLOCK_DATA;
						state <= RECEIVE_BYTE;
					end if;
					sclk_sig <= not sclk_sig;

				when READ_BLOCK_DATA =>
					if (byte_counter = 0) then
						bit_counter := 7;
						return_state <= READ_BLOCK_CRC;
						state <= RECEIVE_BYTE;
					else
						byte_counter := byte_counter - 1;
						return_state <= READ_BLOCK_DATA;
						bit_counter := 7;
						state <= RECEIVE_BYTE;
					end if;
			
				when READ_BLOCK_CRC =>
					bit_counter := 7;
					return_state <= IDLE;
					address <= std_logic_vector(unsigned(address) + x"200");
					state <= RECEIVE_BYTE;
        	
				when SEND_CMD =>
					if (sclk_sig = '1') then
						if (bit_counter = 0) then
							state <= RECEIVE_BYTE_WAIT;
						else
							bit_counter := bit_counter - 1;
							cmd_out <= cmd_out(54 downto 0) & '1';
						end if;
					end if;
					sclk_sig <= not sclk_sig;
				
				when RECEIVE_BYTE_WAIT =>
					if (sclk_sig = '1') then
						if (miso = '0') then
							recv_data <= (others => '0');
							if (response_mode='0') then
								bit_counter := 3; -- already read bits 7..4
							else
								bit_counter := 6; -- already read bit 7
							end if;
							state <= RECEIVE_BYTE;
						end if;
					end if;
					sclk_sig <= not sclk_sig;

				when RECEIVE_BYTE =>
					if (sclk_sig = '1') then
						recv_data <= recv_data(6 downto 0) & miso;
						if (bit_counter = 0) then
							state <= return_state;
							dout <= recv_data(6 downto 0) & miso;
						else
							bit_counter := bit_counter - 1;
						end if;
					end if;
					sclk_sig <= not sclk_sig;

				when WRITE_BLOCK_CMD =>
					cmd_mode <= '1';
					if (data_mode = '0') then
						cmd_out <= x"FF" & x"59" & address & x"FF";	-- continuous
					else
						cmd_out <= x"FF" & x"58" & address & x"FF";	-- single block
					end if;
					bit_counter := 55;
					return_state <= WRITE_BLOCK_INIT;
					state <= SEND_CMD;
					
				when WRITE_BLOCK_INIT => 
					cmd_mode <= '0';
					byte_counter := WRITE_DATA_SIZE; 
					state <= WRITE_BLOCK_DATA;
					
				when WRITE_BLOCK_DATA => 
					if byte_counter = 0 then
						state <= RECEIVE_BYTE_WAIT;
						return_state <= WRITE_BLOCK_WAIT;
						response_mode <= '0';
					else 	
						if ((byte_counter = 2) or (byte_counter = 1)) then
							data_sig <= x"FF"; -- two CRC bytes
						elsif byte_counter = WRITE_DATA_SIZE then
							if (data_mode='0') then
								data_sig <= x"FC"; -- start byte, multiple blocks
							else
								data_sig <= x"FE"; -- start byte, single block
							end if;
						else
							-- just a counter, get real data here
							data_sig <= std_logic_vector(to_unsigned(byte_counter,8));
						end if;
						bit_counter := 7;
						state <= WRITE_BLOCK_BYTE;
						byte_counter := byte_counter - 1;
					end if;
				
				when WRITE_BLOCK_BYTE => 
					if (sclk_sig = '1') then
						if bit_counter=0 then
							state <= WRITE_BLOCK_DATA;
						else
							data_sig <= data_sig(6 downto 0) & '1';
							bit_counter := bit_counter - 1;
						end if;
					end if;
					sclk_sig <= not sclk_sig;
					
				when WRITE_BLOCK_WAIT =>
					response_mode <= '1';
					if sclk_sig='1' then
						if MISO='1' then
							if (data_mode='0') then
								state <= WRITE_BLOCK_INIT;
							else
								address <= std_logic_vector(unsigned(address) + x"200");
								state <= IDLE;
							end if;
						end if;
					end if;
					sclk_sig <= not sclk_sig;

				when others => state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  sclk <= sclk_sig;
  mosi <= cmd_out(55) when cmd_mode='1' else data_sig(7);
  
end rtl;

