LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity KNJRAMCONT is
generic(
	LDR_AWIDTH	:integer	:=19;
	LDR_BGNADDR	:std_logic_vector(23 downto 0)	:=x"040000"
);
port(
	LDR_ADDR	:in std_logic_vector(LDR_AWIDTH-1 downto 0);
	LDR_EN		:in std_logic;
	LDR_WR		:in std_logic;
	LDR_WDAT	:in std_logic_vector(7 downto 0);
	
	ioaddr		:in std_logic_vector(15 downto 0);
	iowr		:in std_logic;
	iord		:in std_logic;
	wrdat		:in std_logic_vector(7 downto 0);

	KNJRAMSEL	:out std_logic_vector(1 downto 0);
	KNJRAMADDR	:out std_logic_vector(16 downto 0);
	KNJRAMWDAT	:out std_logic_vector(7 downto 0);
	KNJRAMWR	:out std_logic;
	KNJRAMOE	:out std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end KNJRAMCONT;

architecture rtl of KNJRAMCONT is
signal	BGNADDR	:std_logic_vector(LDR_AWIDTH-1 downto 0);
signal	ENDADDR	:std_logic_vector(LDR_AWIDTH-1 downto 0);
signal	CGADDR	:std_logic_vector(16 downto 0);
signal	JISCODE	:std_logic_vector(15 downto 0);
signal	CGCODE	:std_logic_vector(15 downto 0);
signal	CPOS	:std_logic_vector(7 downto 0);
signal	KNJRAMSELb	:std_logic_vector(1 downto 0);


component knjaddrcnv
port(
	kcode	:in std_logic_vector(15 downto 0);
	cline	:in std_logic_vector(3 downto 0);
	
	romsel	:out std_logic_vector(1 downto 0);
	romaddr	:out std_logic_vector(16 downto 0)
);
end component;

begin
	BGNADDR<=LDR_BGNADDR(LDR_AWIDTH-1 downto 0);
	ENDADDR(LDR_AWIDTH-1 downto 18)<=LDR_BGNADDR(LDR_AWIDTH-1 downto 18);
	ENDADDR(17 downto 0)<=(others=>'1');

	process(clk,rstn)begin
		if(rstn='0')then
			JISCODE<=(others=>'0');
			CPOS<=(others=>'0');
		elsif(clk' event and clk='1')then
			if(iowr='1')then
				case ioaddr is
				when x"00a1" =>
					JISCODE(15 downto 8)<=wrdat;
				when x"00a3" =>
					JISCODE(7 downto 0)<=wrdat;
				when x"00a5" =>
					CPOS<=wrdat;
				when others=>
				end case;
			end if;
		end if;
	end process;
	
	-- ANK characters have no left/right half. Keep their high byte zero.
	CGCODE<=JISCODE when JISCODE(15 downto 8)=x"00" else
			not CPOS(5) & JISCODE(14 downto 0);
	cnv	:knjaddrcnv port map(
		kcode	=>CGCODE,
		cline	=>CPOS(3 downto 0),
		
		romsel	=>KNJRAMSELb,
		romaddr	=>CGADDR
	);
	
	KNJRAMADDR<=LDR_ADDR(16 downto 0) when LDR_EN='1' else CGADDR;
	KNJRAMSEL<=	'0' & LDR_ADDR(17) when LDR_EN='1' else KNJRAMSELb;
	
	KNJRAMWR<=	LDR_WR	when LDR_EN='1' and LDR_ADDR>=BGNADDR and LDR_ADDR<=ENDADDR else
				iowr	when ioaddr=x"00a9" else
				'0';
	KNJRAMOE<=	iord	when ioaddr=x"00a9" else '0';
	KNJRAMWDAT<=	LDR_WDAT when LDR_EN='1' else
					wrdat;
	end rtl;