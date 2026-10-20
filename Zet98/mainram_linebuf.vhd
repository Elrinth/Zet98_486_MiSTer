LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Read line buffer for CPU reads of main RAM (below A0000h).
-- A miss fetches the aligned four-word SDRAM group with one CPURD4 burst
-- (the path the GRCG uses for four planes) instead of a CPURD1 per word, so
-- one ~22-clock controller round trip serves four words. Every SDRAM write on
-- the CPU port (CPU, DMA, GRCG/EGC, loader) to the buffered group drops the
-- line; the tag is the physical SDRAM word address, so bank windows cannot
-- alias it. The controller drains posted writes before any read, so a fill
-- never returns data older than a write already acknowledged.
-- No state or acknowledge depends on the live decoded bus address in the
-- clock it appears: a request is registered first and looked up on the next
-- clock (hit acknowledge after two clocks). The earlier same-clock tag compare
-- missed timing at 90 MHz and returned wrong data on hardware (Briganty
-- B228W; Doom, Windows 95, CONVTEST in B262 tests). A write's snoop compare
-- is registered as one bit: every CPU-port write stays requested over at
-- least two clock edges (its acknowledge is registered and the requester sees
-- it a clock later), so a late first compare is repeated with a settled
-- address, and a false match only drops the line.
-- The bus must drop the request after each acknowledge (ao486_memory_bridge
-- RELEASE does), since a held request is not compared against a new address.
entity mainram_linebuf is
generic(
	AW	:integer	:=22
);
port(
	elig		:in std_logic;							-- CPU main-RAM access (not DMA)
	mrd			:in std_logic;
	bank		:in std_logic_vector(1 downto 0);
	addr		:in std_logic_vector(AW-1 downto 0);	-- SDRAM word address

	snoop_wr	:in std_logic;							-- any CPU-port SDRAM write
	snoop_bank	:in std_logic_vector(1 downto 0);
	snoop_addr	:in std_logic_vector(AW-1 downto 0);
	flush		:in std_logic;

	sdr_ack		:in std_logic;
	sdr_rdat0	:in std_logic_vector(15 downto 0);
	sdr_rdat1	:in std_logic_vector(15 downto 0);
	sdr_rdat2	:in std_logic_vector(15 downto 0);
	sdr_rdat3	:in std_logic_vector(15 downto 0);

	rd4			:out std_logic;							-- burst request (miss)
	ack			:out std_logic;							-- hit acknowledge
	doe			:out std_logic;							-- drive read data
	rdat		:out std_logic_vector(15 downto 0);
	-- The odd word after an even request (same line) is available with the
	-- acknowledge, so a 486 dword read needs one bus transfer, not two.
	-- From registered state only: FILL/HOLD exist only while the buffer
	-- serves the current request (a request is dropped after its ACK).
	dw			:out std_logic;
	rdat_hi		:out std_logic_vector(15 downto 0);

	clk			:in std_logic;
	rstn		:in std_logic
);
end mainram_linebuf;

architecture rtl of mainram_linebuf is
type state_t is (st_IDLE, st_LOOK, st_FILL, st_HOLD);
signal	state	:state_t;
signal	req		:std_logic;
signal	valid	:std_logic;
signal	tag		:std_logic_vector(AW-1 downto 2);
signal	tagbank	:std_logic_vector(1 downto 0);
signal	laddr	:std_logic_vector(AW-1 downto 0);
signal	lbank	:std_logic_vector(1 downto 0);
subtype word_t is std_logic_vector(15 downto 0);
type line_t is array(0 to 3) of word_t;
signal	line	:line_t;
signal	fillword	:word_t;
signal	hit		:std_logic;
signal	shit	:std_logic;
signal	sflush	:std_logic;
begin
	req<=elig and mrd;
	-- Registered operands only (laddr/lbank are the request latched in IDLE).
	hit<='1' when valid='1' and tagbank=lbank and tag=laddr(AW-1 downto 2) else '0';

	with laddr(1 downto 0) select fillword<=
		sdr_rdat0 when "00",
		sdr_rdat1 when "01",
		sdr_rdat2 when "10",
		sdr_rdat3 when others;

	rd4<='1' when state=st_FILL and req='1' else '0';
	doe<='1' when req='1' and (state=st_FILL or state=st_HOLD) else '0';
	rdat<=fillword when state=st_FILL else line(conv_integer(laddr(1 downto 0)));
	dw<='1' when (state=st_FILL or state=st_HOLD) and laddr(0)='0' else '0';
	rdat_hi<=	sdr_rdat3 when state=st_FILL and laddr(1)='1' else
				sdr_rdat1 when state=st_FILL else
				line(3) when laddr(1)='1' else
				line(1);

	process(clk,rstn)begin
		if(rstn='0')then
			state<=st_IDLE;
			valid<='0';
			ack<='0';
			shit<='0';
			sflush<='0';
		elsif(clk' event and clk='1')then
			ack<='0';
			-- A write's snoop lands one clock late. The bus needs at least
			-- three clocks after a write's acknowledge (RELEASE, IDLE, the
			-- next request, then LOOK) before a lookup.
			if(snoop_wr='1' and snoop_bank=tagbank and snoop_addr(AW-1 downto 2)=tag)then
				shit<='1';
			else
				shit<='0';
			end if;
			sflush<=flush;
			case state is
			when st_IDLE =>
				if(req='1')then
					laddr<=addr;
					lbank<=bank;
					state<=st_LOOK;
				end if;
			when st_LOOK =>
				if(req='0')then
					state<=st_IDLE;
				elsif(hit='1')then
					ack<='1';
					state<=st_HOLD;
				else
					state<=st_FILL;
				end if;
			when st_FILL =>
				if(req='0')then
					state<=st_IDLE;
				elsif(sdr_ack='1')then
					line(0)<=sdr_rdat0;
					line(1)<=sdr_rdat1;
					line(2)<=sdr_rdat2;
					line(3)<=sdr_rdat3;
					tag<=laddr(AW-1 downto 2);
					tagbank<=lbank;
					valid<='1';
					state<=st_HOLD;
				end if;
			when st_HOLD =>
				if(req='0')then
					state<=st_IDLE;
				end if;
			end case;
			-- Coherence last: a write to the buffered group always wins.
			if(sflush='1' or shit='1')then
				valid<='0';
			end if;
		end if;
	end process;
end rtl;
