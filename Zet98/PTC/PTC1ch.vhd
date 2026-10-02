LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PTC1ch is
port(
	RD		:in std_logic;
	WR		:in std_logic;
	RDAT	:out std_logic_vector(7 downto 0);
	WDAT	:in std_logic_vector(7 downto 0);
	OE		:out std_logic;
	
	RWMODE	:in std_logic_vector(1 downto 0);
	CNTLAT	:in std_logic;
	OPMODE	:in std_logic_vector(2 downto 0);
	OPBCD	:in std_logic;
	CTLWR	:in std_logic;							-- control word for this channel
	CTLMODE	:in std_logic_vector(2 downto 0);		-- its mode field
	
	CNTIN	:in std_logic;
	TRIG	:in std_logic;
	CNTOUT	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end PTC1ch;

architecture rtl of PTC1ch is
signal	CURCOUNT	:std_logic_vector(15 downto 0);
signal	RETCOUNT	:std_logic_vector(15 downto 0);
signal	LATCOUNT	:std_logic_vector(15 downto 0);
signal	DATH_Ln		:std_logic;
signal	DECVAL		:std_logic_vector(15 downto 0);
signal	HALFVAL		:std_logic_vector(15 downto 0);
signal	CNTBGN		:std_logic;
signal	PERCOUNT	:std_logic_vector(15 downto 0);	-- count of the running period
signal	LOADING		:std_logic;						-- control word written, count not yet
signal	LSBHOLD		:std_logic_vector(7 downto 0);
signal	WDATL		:std_logic_vector(7 downto 0);
signal	lWRC		:std_logic;
signal	OUTR		:std_logic;						-- OUT (readable copy of CNTOUT)
signal	LATCHED		:std_logic;						-- latched count not read yet
begin

	process(clk,rstn)
	variable lTRIG	:std_logic;
	begin
		if(rstn='0')then
			CNTBGN<='0';
			lTRIG:='0';
		elsif(clk' event and clk='1')then
			CNTBGN<='0';
			if(lTRIG='0' and TRIG='1')then
				CNTBGN<='1';
			end if;
			lTRIG:=TRIG;
		end if;
	end process;

	process(clk,rstn)
	variable lRD,lWR	:std_logic;
	begin
		if(rstn='0')then
			DATH_Ln<='0';
			lRD:='0';
			lWR:='0';
		elsif(clk' event and clk='1')then
			case RWMODE is
			when "11" =>
				if(CTLWR='1')then
					DATH_Ln<='0';		-- a control word restarts with the LSB
				elsif((lRD='1' and RD='0') or (lWR='1' and WR='0'))then
					DATH_Ln<=not DATH_Ln;
				end if;
			when "10" =>
				DATH_Ln<='1';
			when "01" =>
				DATH_Ln<='0';
			when others =>
			end case;
			lRD:=RD;
			lWR:=WR;
		end if;
	end process;

	-- Counter latch: the count is held until it has been read (both bytes in
	-- LSB/MSB mode); a second latch before that is ignored. Without a pending
	-- latch a read returns the running count, as on the 8253.
	process(clk,rstn)
	variable lRDL	:std_logic;
	begin
		if(rstn='0')then
			LATCOUNT<=(others=>'0');
			LATCHED<='0';
			lRDL:='0';
		elsif(clk' event and clk='1')then
			if(LATCHED='0')then
				LATCOUNT<=CURCOUNT;
				if(CNTLAT='1')then
					LATCHED<='1';
				end if;
			elsif(lRDL='1' and RD='0')then
				if(RWMODE/="11" or DATH_Ln='1')then
					LATCHED<='0';
				end if;
			end if;
			lRDL:=RD;
		end if;
	end process;

	-- 8253 count loading. A control word sets OUT to its initial state (low
	-- in mode 0, else high) and stops the counter until the whole count is
	-- written (LSB only / MSB only with the other byte 0, or LSB then MSB).
	-- Modes 0 and 4 restart on every new count; in the periodic modes 2 and 3
	-- a count written without a control word takes effect at the next reload.
	-- Applying bytes as they arrived made mode 3 OUT dip and rise again while
	-- a timer ISR reprogrammed it: a spurious IRQ0 edge on every tick
	-- (Might and Magic III's music driver after the BIOS interval timer).
	process(clk,rstn)
	variable newcnt	:std_logic_vector(15 downto 0);
	variable done	:boolean;
	begin
		if(rstn='0')then
			CURCOUNT<=(others=>'0');
			RETCOUNT<=(others=>'0');
			PERCOUNT<=(others=>'0');
			OUTR<='0';
			LOADING<='0';
			LSBHOLD<=(others=>'0');
			WDATL<=(others=>'0');
			lWRC<='0';
		elsif(clk' event and clk='1')then
			lWRC<=WR;
			if(WR='1')then
				WDATL<=WDAT;
			end if;
			done:=false;
			newcnt:=RETCOUNT;
			if(lWRC='1' and WR='0')then		-- a count byte write has ended
				case RWMODE is
				when "01" =>
					newcnt:=x"00" & WDATL; done:=true;
				when "10" =>
					newcnt:=WDATL & x"00"; done:=true;
				when others =>
					if(DATH_Ln='0')then
						LSBHOLD<=WDATL;
					else
						newcnt:=WDATL & LSBHOLD; done:=true;
					end if;
				end case;
			end if;
			if(CTLWR='1')then
				LOADING<='1';
				if(CTLMODE="000")then
					OUTR<='0';
				else
					OUTR<='1';
				end if;
			elsif(done)then
				RETCOUNT<=newcnt;
				case OPMODE is
				when "001" | "101" =>			-- triggered: wait for the gate
					LOADING<='0';
				when "000" | "100" =>
					CURCOUNT<=newcnt; PERCOUNT<=newcnt;
					LOADING<='0';
					OUTR<='0';
				when others =>					-- 2, 3: reload later unless just programmed
					if(LOADING='1')then
						CURCOUNT<=newcnt; PERCOUNT<=newcnt;
						LOADING<='0';
						OUTR<='1';
					end if;
				end case;
			elsif(LOADING='0')then
				case OPMODE is
				when "000" =>
					if(CNTIN='1')then
						if(CURCOUNT=x"0001")then
							OUTR<='1';
						else
							CURCOUNT<=DECVAL;
						end if;
					end if;
				when "100" =>
					if(CNTIN='1')then
						if(CURCOUNT>x"0000")then
							if(CURCOUNT=x"0001")then
								OUTR<='1';
							end if;
							CURCOUNT<=DECVAL;
						else
							OUTR<='0';
						end if;
					end if;
				when "001" | "101" =>
					if(CNTBGN='1')then
						CURCOUNT<=RETCOUNT;
						OUTR<='0';
					elsif(CNTIN='1')then
						if(CURCOUNT>x"0000")then
							if(CURCOUNT=x"0001")then
								OUTR<='1';
							end if;
							CURCOUNT<=DECVAL;
						elsif(OPMODE="101")then
							OUTR<='0';
						end if;
					end if;
				when "010" | "110" =>
					if(CNTIN='1')then
						if(CURCOUNT=x"0001")then
							OUTR<='1';
							CURCOUNT<=RETCOUNT; PERCOUNT<=RETCOUNT;
						else
							OUTR<='0';
							CURCOUNT<=DECVAL;
						end if;
					end if;
				when "011" | "111" =>
					-- Square wave as on the 8253: the count steps down by 2 and
					-- reloads at the end of each half, so a count written without
					-- a control word applies from the next half. OUT starts high;
					-- with an odd count the high half lasts (N+1)/2 inputs and the
					-- low half (N-1)/2. IRQ0 (rising edge) comes once per period.
					-- Windows 95's VTD times itself from latched mode 3 reads.
					if(OPBCD='1')then
						if(CNTIN='1')then
							if(CURCOUNT=x"0001")then
								CURCOUNT<=RETCOUNT; PERCOUNT<=RETCOUNT;
							else
								CURCOUNT<=DECVAL;
							end if;
						end if;
						if(CURCOUNT>HALFVAL)then
							OUTR<='1';
						else
							OUTR<='0';
						end if;
					elsif(CNTIN='1')then
						if(CURCOUNT=x"0002" or (OUTR='0' and CURCOUNT=x"0003"))then
							OUTR<=not OUTR;
							CURCOUNT<=RETCOUNT; PERCOUNT<=RETCOUNT;
						elsif(CURCOUNT(0)='1')then
							if(OUTR='1')then
								CURCOUNT<=CURCOUNT-x"0001";
							else
								CURCOUNT<=CURCOUNT-x"0003";
							end if;
						else
							CURCOUNT<=CURCOUNT-x"0002";
						end if;
					end if;
				when others =>
				end case;
			end if;
		end if;
	end process;
					
	process(CURCOUNT,OPBCD)begin
		if(OPBCD='1')then
			if(CURCOUNT(3 downto 0)/=x"0")then
				DECVAL<=CURCOUNT-x"0001";
			else
				if(CURCOUNT(7 downto 4)/="0")then
					DECVAL<=CURCOUNT(15 downto 8) & (CURCOUNT(7 downto 4)-x"1") & x"0";
				else
					if(CURCOUNT(11 downto 8)/=x"0")then	
						DECVAL<=CURCOUNT(15 downto 12) & (CURCOUNT(11 downto 8)-x"1") & x"00";
					else
						DECVAL<=(CURCOUNT(15 downto 12) - x"1") & x"000";
					end if;
				end if;
			end if;
		else
			DECVAL<=CURCOUNT-x"0001";
		end if;
	end process;
	
	process(PERCOUNT,OPBCD)
	variable	tmp100,tmp10,tmp1	:std_logic_vector(4 downto 0);
	begin
		if(OPBCD='1')then
			HALFVAL(15 downto 12)<='0' & PERCOUNT(15 downto 13);
			if(PERCOUNT(12)='1')then
				tmp100:=('0' & PERCOUNT(11 downto 8))+"01010";
			else
				tmp100:='0' & PERCOUNT(11 downto 8);
			end if;
			HALFVAL(11 downto 8)<=tmp100(4 downto 1);
			if(tmp100(0)='1')then
				tmp10:=('0' & PERCOUNT(7 downto 4))+"01010";
			else
				tmp10:='0' & PERCOUNT(7 downto 4);
			end if;
			HALFVAL(7 downto 4)<=tmp10(4 downto 1);
			if(tmp10(0)='1')then
				tmp1:=('0' & PERCOUNT(3 downto 0))+"01010";
			else
				tmp1:='0' & PERCOUNT(3 downto 0);
			end if;
			HALFVAL(3 downto 0)<=tmp1(4 downto 1);
		else
			HALFVAL<='0' & PERCOUNT(15 downto 1);
		end if;
	end process;
	
	RDAT<=	LATCOUNT(7 downto 0) when DATH_Ln='0' else
			LATCOUNT(15 downto 8);
	OE<=RD;
	CNTOUT<=OUTR;

end rtl;
