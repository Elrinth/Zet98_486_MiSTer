LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity GAIJIRAMDP is
PORT
(
	address_a		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	address_b		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	clock_a		: IN STD_LOGIC  := '1';
	clock_b		: IN STD_LOGIC ;
	data_a		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	data_b		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	wren_a		: IN STD_LOGIC  := '0';
	wren_b		: IN STD_LOGIC  := '0';
	q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
	q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
);
end GAIJIRAMDP;

architecture rtl of GAIJIRAMDP is
-- FONT.ROM has 0x6800 bytes beyond its first two 128-KiB banks.
-- Keep the custom-character window within that complete writable tail.
constant RAM_BLOCKS : integer := 13; -- 13 x 2 KiB = 26 KiB
signal	addramod	:std_logic_vector(16 downto 0);
signal	addrbmod	:std_logic_vector(16 downto 0);
subtype datbuf is std_logic_vector(7 downto 0); 
type datbuf_array is array (natural range <>) of datbuf; 
signal	qabuf	:datbuf_array(0 to RAM_BLOCKS-1);
signal	qbbuf	:datbuf_array(0 to RAM_BLOCKS-1);
signal	wea		:std_logic_vector(RAM_BLOCKS-1 downto 0);
signal	web		:std_logic_vector(RAM_BLOCKS-1 downto 0);
signal	cena	:std_logic_vector(RAM_BLOCKS-1 downto 0);
signal	cenb	:std_logic_vector(RAM_BLOCKS-1 downto 0);

component DPSRAM11x8
	PORT
	(
		address_a		: IN STD_LOGIC_VECTOR (10 DOWNTO 0);
		address_b		: IN STD_LOGIC_VECTOR (10 DOWNTO 0);
		clock_a		: IN STD_LOGIC  := '1';
		clock_b		: IN STD_LOGIC ;
		data_a		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		data_b		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		wren_a		: IN STD_LOGIC  := '0';
		wren_b		: IN STD_LOGIC  := '0';
		q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END component;
begin
	addramod<=address_a;
	addrbmod<=address_b;
	process(address_a,address_b)begin
		cena<=(others=>'0');
		cenb<=(others=>'0');
		if(address_a<('0' & x"6800"))then
			cena(conv_integer(address_a(16 downto 11)))<='1';
		end if;
		if(address_b<('0' & x"6800"))then
			cenb(conv_integer(address_b(16 downto 11)))<='1';
		end if;
	end process;

	wea<=cena when wren_a='1' else (others=>'0');
	web<=cenb when wren_b='1' else (others=>'0');
	
	ramb	:for i in 0 to RAM_BLOCKS-1 generate
		ram0	:DPSRAM11x8 port map(
			address_a		=>addramod(10 downto 0),
			address_b		=>addrbmod(10 downto 0),
			clock_a			=>clock_a,
			clock_b			=>clock_b,
			data_a			=>data_a,
			data_b			=>data_b,
			wren_a			=>wea(i),
			wren_b			=>web(i),
			q_a				=>qabuf(i),
			q_b				=>qbbuf(i)
		);
	end generate;
	
	process(cena,qabuf)
	variable tmp	:std_logic_vector(7 downto 0);
	begin
		tmp:=(others=>'0');
		for i in 0 to RAM_BLOCKS-1 loop
			if(cena(i)='1')then
				tmp:=qabuf(i);
			end if;
		end loop;
		q_a<=tmp;
	end process;

	process(cenb,qbbuf)
	variable tmp	:std_logic_vector(7 downto 0);
	begin
		tmp:=(others=>'0');
		for i in 0 to RAM_BLOCKS-1 loop
			if(cenb(i)='1')then
				tmp:=qbbuf(i);
			end if;
		end loop;
		q_b<=tmp;
	end process;
	
end rtl;
