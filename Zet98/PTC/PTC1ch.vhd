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
	STLAT	:in std_logic;							-- read-back status latch
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
signal	CNTOUTR		:std_logic;
signal	LATCHED		:std_logic;						-- LATCOUNT not yet read out
signal	STPEND		:std_logic;						-- STATBYTE not yet read
signal	STATBYTE	:std_logic_vector(7 downto 0);
signal	RDCOUNT		:std_logic_vector(15 downto 0);
signal	DECVAL		:std_logic_vector(15 downto 0);
signal	HALFVAL		:std_logic_vector(15 downto 0);
signal	CNTBGN		:std_logic;
signal	PERCOUNT	:std_logic_vector(15 downto 0);	-- count of the running period
signal	LOADING		:std_logic;						-- control word written, count not yet
signal	LSBHOLD		:std_logic_vector(7 downto 0);
signal	WDATL		:std_logic_vector(7 downto 0);
signal	lWRC		:std_logic;
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

	-- Reads return a latched count (counter latch or read-back command) until
	-- it has been read out, else the running count as on the 8253 (NP2kai
	-- getcount). Returning only the last latch froze any code that polls the
	-- counter without latching, or latches with read-back: MSDET.DLL's CLI
	-- delay (D2h, then port 71h) spun forever in Win95 Setup's MPU-401 probe.
	-- A latched read-back status byte is read first and leaves the LSB/MSB
	-- flip-flop alone. A newer latch replaces an unread one, as in NP2kai.
	process(clk,rstn)
	variable lRD,lWR	:std_logic;
	begin
		if(rstn='0')then
			DATH_Ln<='0';
			LATCHED<='0';
			STPEND<='0';
			LATCOUNT<=(others=>'0');
			STATBYTE<=(others=>'0');
			lRD:='0';
			lWR:='0';
		elsif(clk' event and clk='1')then
			if(lRD='1' and RD='0')then
				if(STPEND='1')then
					STPEND<='0';
				elsif(RWMODE/="11" or DATH_Ln='1')then
					LATCHED<='0';
				end if;
			end if;
			case RWMODE is
			when "11" =>
				if(CTLWR='1')then
					DATH_Ln<='0';		-- a control word restarts with the LSB
				elsif((lRD='1' and RD='0' and STPEND='0') or (lWR='1' and WR='0'))then
					DATH_Ln<=not DATH_Ln;
				end if;
			when "10" =>
				DATH_Ln<='1';
			when "01" =>
				DATH_Ln<='0';
			when others =>
			end case;
			if(CTLWR='1')then
				LATCHED<='0';
				STPEND<='0';
			end if;
			if(CNTLAT='1')then
				LATCOUNT<=CURCOUNT;
				LATCHED<='1';
			end if;
			if(STLAT='1')then
				STATBYTE<=CNTOUTR & LOADING & RWMODE & OPMODE & OPBCD;
				STPEND<='1';
			end if;
			lRD:=RD;
			lWR:=WR;
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
			CNTOUTR<='0';
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
					CNTOUTR<='0';
				else
					CNTOUTR<='1';
				end if;
			elsif(done)then
				RETCOUNT<=newcnt;
				case OPMODE is
				when "001" | "101" =>			-- triggered: wait for the gate
					LOADING<='0';
				when "000" | "100" =>
					CURCOUNT<=newcnt; PERCOUNT<=newcnt;
					LOADING<='0';
					CNTOUTR<='0';
				when others =>					-- 2, 3: reload later unless just programmed
					if(LOADING='1')then
						CURCOUNT<=newcnt; PERCOUNT<=newcnt;
						LOADING<='0';
						CNTOUTR<='1';
					end if;
				end case;
			elsif(LOADING='0')then
				case OPMODE is
				when "000" =>
					if(CNTIN='1')then
						if(CURCOUNT=x"0001")then
							CNTOUTR<='1';
						else
							CURCOUNT<=DECVAL;
						end if;
					end if;
				when "100" =>
					if(CNTIN='1')then
						if(CURCOUNT>x"0000")then
							if(CURCOUNT=x"0001")then
								CNTOUTR<='1';
							end if;
							CURCOUNT<=DECVAL;
						else
							CNTOUTR<='0';
						end if;
					end if;
				when "001" | "101" =>
					if(CNTBGN='1')then
						CURCOUNT<=RETCOUNT;
						CNTOUTR<='0';
					elsif(CNTIN='1')then
						if(CURCOUNT>x"0000")then
							if(CURCOUNT=x"0001")then
								CNTOUTR<='1';
							end if;
							CURCOUNT<=DECVAL;
						elsif(OPMODE="101")then
							CNTOUTR<='0';
						end if;
					end if;
				when "010" | "110" =>
					if(CNTIN='1')then
						if(CURCOUNT=x"0001")then
							CNTOUTR<='1';
							CURCOUNT<=RETCOUNT; PERCOUNT<=RETCOUNT;
						else
							CNTOUTR<='0';
							CURCOUNT<=DECVAL;
						end if;
					end if;
				when "011" | "111" =>
					if(CNTIN='1')then
						if(CURCOUNT=x"0001")then
							CURCOUNT<=RETCOUNT; PERCOUNT<=RETCOUNT;
						else
							CURCOUNT<=DECVAL;
						end if;
					end if;
					-- Square wave: OUT is high for the first half of each period
					-- ((N+1)/2 counts) and low for the second, as on the 8253. A
					-- reload restarts high, so the next rising edge (IRQ0) comes
					-- after a full period; low-first made the BIOS interval timer,
					-- which reloads from its callback, tick every half period.
					if(CURCOUNT>HALFVAL)then
						CNTOUTR<='1';
					else
						CNTOUTR<='0';
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
	
	RDCOUNT<=LATCOUNT when LATCHED='1' else CURCOUNT;
	RDAT<=	STATBYTE when STPEND='1' else
			RDCOUNT(7 downto 0) when DATH_Ln='0' else
			RDCOUNT(15 downto 8);
	OE<=RD;
	CNTOUT<=CNTOUTR;

end rtl;
