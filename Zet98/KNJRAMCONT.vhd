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
	-- CG window (A4000h-A4FFFh): while cgw_en, the pattern line and half
	-- come from the window address instead of port A5h.
	cgw_en		:in std_logic := '0';
	cgw_right	:in std_logic := '0';
	cgw_line	:in std_logic_vector(3 downto 0) := (others=>'0');
	cgw_wr		:in std_logic := '0';
	cgw_wdat	:in std_logic_vector(7 downto 0) := (others=>'0');

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
signal	LDR_EXTADDR	:std_logic_vector(23 downto 0);
signal	ENDADDR	:std_logic_vector(23 downto 0);
signal	FONT_OFFSET	:std_logic_vector(23 downto 0);
signal	CGADDR	:std_logic_vector(16 downto 0);
signal	JISCODE	:std_logic_vector(15 downto 0);
signal	CGCODE	:std_logic_vector(15 downto 0);
signal	CGKANJI	:std_logic;
signal	CPOS	:std_logic_vector(7 downto 0);
signal	KNJRAMSELb	:std_logic_vector(1 downto 0);
signal	CLINE	:std_logic_vector(3 downto 0);


component knjaddrcnv
port(
	kcode	:in std_logic_vector(15 downto 0);
	cline	:in std_logic_vector(3 downto 0);
	force_kanji	:in std_logic;

	romsel	:out std_logic_vector(1 downto 0);
	romaddr	:out std_logic_vector(16 downto 0)
);
end component;

begin
	-- The 0x46800-byte FONT.ROM spans two full banks and a third tail.
	LDR_EXTADDR(23 downto LDR_AWIDTH)<=(others=>'0');
	LDR_EXTADDR(LDR_AWIDTH-1 downto 0)<=LDR_ADDR;
	FONT_OFFSET<=LDR_EXTADDR-LDR_BGNADDR;
	ENDADDR<=LDR_BGNADDR+x"0467ff";

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
	CLINE<=cgw_line when cgw_en='1' else CPOS(3 downto 0);
	CGCODE<=JISCODE when JISCODE(15 downto 8)=x"00" else
			cgw_right & JISCODE(14 downto 0) when cgw_en='1' else     -- odd address: right half
			not CPOS(5) & JISCODE(14 downto 0);
	CGKANJI<='0' when JISCODE(15 downto 8)=x"00" else '1';
	-- Port A1h bit 7 is dropped like NP2kai's code & 7F7Fh, so user character
	-- 7680h shares a slot with 7600h. It must stay a Kanji-ROM access even
	-- when the half flag leaves the high byte zero, or its left half would
	-- overwrite ANK 'V'.
	cnv	:knjaddrcnv port map(
		kcode	=>CGCODE,
		cline	=>CLINE,
		force_kanji	=>CGKANJI,

		romsel	=>KNJRAMSELb,
		romaddr	=>CGADDR
	);
	
	KNJRAMADDR<=FONT_OFFSET(16 downto 0) when LDR_EN='1' else CGADDR;
	KNJRAMSEL<=	FONT_OFFSET(18 downto 17) when LDR_EN='1' else KNJRAMSELb;
	
	KNJRAMWR<=	LDR_WR	when LDR_EN='1' and LDR_EXTADDR>=LDR_BGNADDR and LDR_EXTADDR<=ENDADDR else
				iowr	when LDR_EN='0' and ioaddr=x"00a9" else
				cgw_wr	when LDR_EN='0' and cgw_en='1' else
				'0';
	KNJRAMOE<=	iord	when ioaddr=x"00a9" else '0';
	KNJRAMWDAT<=	LDR_WDAT when LDR_EN='1' else
					cgw_wdat when cgw_en='1' else
					wrdat;
	end rtl;