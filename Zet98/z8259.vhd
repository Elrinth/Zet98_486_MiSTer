LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_arith.all;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity z8259 is
generic(
	monlen	:integer	:=15
);
port(
	CS		:in std_logic;
	ADDR	:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	RD		:in std_logic;
	WR		:in std_logic;
	
	IR0		:in std_logic;
	IR1		:in std_logic;
	IR2		:in std_logic;
	IR3		:in std_logic;
	IR4		:in std_logic;
	IR5		:in std_logic;
	IR6		:in std_logic;
	IR7		:in std_logic;
	
--	LEN0	:out std_logic_vector(monlen-1 downto 0);
--	LEN1	:out std_logic_vector(monlen-1 downto 0);
--	LEN2	:out std_logic_vector(monlen-1 downto 0);
--	LEN3	:out std_logic_vector(monlen-1 downto 0);
--	LEN4	:out std_logic_vector(monlen-1 downto 0);
--	LEN5	:out std_logic_vector(monlen-1 downto 0);
--	LEN6	:out std_logic_vector(monlen-1 downto 0);
--	LEN7	:out std_logic_vector(monlen-1 downto 0);
--	
	INT		:out std_logic;
	INTA	:in std_logic;
	
	CASI	:in std_logic_vector(2 downto 0);
	CASO	:out std_logic_vector(2 downto 0);
	CASM	:in std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end z8259;

architecture rtl of z8259 is
signal	ICW4	:std_logic;
signal	SNGL	:std_logic;
signal	L_En	:std_logic;
signal	VECT	:std_logic_vector(4 downto 0);
signal	TOSLAVE	:std_logic_vector(7 downto 0);
signal	SLID	:std_logic_vector(2 downto 0);
signal	AEOI	:std_logic;
signal	M_Sn	:std_logic;
signal	BUF		:std_logic;
signal	SFNM	:std_logic;
signal	ICW		:integer range 0 to 3;
signal	IRx		:std_logic_vector(7 downto 0);
signal	IMR		:std_logic_vector(7 downto 0);
signal	IRR		:std_logic_vector(7 downto 0);
signal	ISR		:std_logic_vector(7 downto 0);
signal	lIRx		:std_logic_vector(7 downto 0);
signal	S_LEV	:std_logic_vector(2 downto 0);
signal	RIS		:std_logic;
signal	RR		:std_logic;
signal	POLL	:std_logic;
signal	SMMODE	:std_logic;
signal	SET_OC3	:std_logic;

signal	CWR		:std_logic;
signal	lWR		:std_logic;
signal	lADDR	:std_logic;
signal	lDIN	:std_logic_vector(7 downto 0);

signal	IRM		:std_logic_vector(7 downto 0);
signal	lIRM	:std_logic_vector(7 downto 0);
signal	IRL		:std_logic_vector(7 downto 0);
signal	LCLR	:std_logic;
signal	LCx		:integer range 0 to 7;
signal	INTnum	:integer range 0 to 7;
signal	PRI		:integer range 0 to 7;
signal	IVECT	:std_logic_vector(7 downto 0);
signal	lINTA	:std_logic;
signal	AROT	:std_logic;
signal	command	:std_logic_vector(2 downto 0);
constant cmd_RES_ROTAUTOEOI	:std_logic_vector(2 downto 0)	:="000";
constant cmd_NSEOI			:std_logic_vector(2 downto 0)	:="001";
constant cmd_NOP			:std_logic_vector(2 downto 0)	:="010";
constant cmd_SEOI			:std_logic_vector(2 downto 0)	:="011";
constant cmd_SET_ROTAUTOEOI	:std_logic_vector(2 downto 0)	:="100";
constant cmd_ROTONNSEOI		:std_logic_vector(2 downto 0)	:="101";
constant cmd_SETPRIO		:std_logic_vector(2 downto 0)	:="110";
constant cmd_ROTONSEOI		:std_logic_vector(2 downto 0)	:="111";
signal	ROTINAEOI	:std_logic;
signal	ROTONSEOI	:std_logic;
signal	INTb		:std_logic;
signal	ISnum		:integer range 0 to 8;
signal	mISnum		:integer range 0 to 8;
signal	lEOI		:integer range 5 downto 0;
signal	INTAm		:std_logic;

component signlen
generic(
	lwidth	:integer	:=8
);
port(
	sig		:in std_logic;
	
	len		:out std_logic_vector(lwidth-1 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;
begin
	INTAm<=	INTA when M_Sn='1' else
				INTA when (M_Sn='0' and SLID=CASI) else
				'0';
	
	CWR<=WR and CS;
--	ln0	:signlen generic map(monlen)port map(ISR(0),LEN0,clk,rstn);
--	ln1	:signlen generic map(monlen)port map(ISR(1),LEN1,clk,rstn);
--	ln2	:signlen generic map(monlen)port map(ISR(2),LEN2,clk,rstn);
--	ln3	:signlen generic map(monlen)port map(ISR(3),LEN3,clk,rstn);
--	ln4	:signlen generic map(monlen)port map(ISR(4),LEN4,clk,rstn);
--	ln5	:signlen generic map(monlen)port map(ISR(5),LEN5,clk,rstn);
--	ln6	:signlen generic map(monlen)port map(ISR(6),LEN6,clk,rstn);
--	ln7	:signlen generic map(monlen)port map(ISR(7),LEN7,clk,rstn);
	
	process(clk,rstn)begin
		if(rstn='0')then
			lWR<='0';
			lADDR<='0';
			lDIN<=(others=>'0');
		elsif(clk' event and clk='1')then
			lWR<=CWR;
			if(CWR='1')then
				lADDR<=ADDR;
				lDIN<=DIN;
			end if;
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			ICW4<='0';
			SNGL<='0';
			L_En<='0';
			VECT<=(others=>'0');
			TOSLAVE<=(others=>'0');
			SLID<=(others=>'0');
			AEOI<='0';
			M_Sn<='0';
			BUF<='0';
			SFNM<='0';
			IMR<=(others=>'0');
			S_LEV<=(others=>'0');
			RIS<='0';
			RR<='0';
			POLL<='0';
			SET_OC3<='0';
			ICW<=0;
			AROT<='0';
			command<=cmd_NOP;
			ROTINAEOI<='0';
			ROTONSEOI<='1';
			SMMODE<='0';
		elsif(clk' event and clk='1')then
			command<=cmd_NOP;
			SET_OC3<='0';
			if(lWR='1' and CWR='0')then
				if(lADDR='0')then
					if(lDIN(4)='1')then	--ICW1
						ICW<=0;
						ICW4<=lDIN(0);
						SNGL<=lDIN(1);
						L_En<=lDIN(3);
					elsif(lDIN(3)='0')then	--OCW2
						command<=lDIN(7 downto 5);
						case(lDIN(7 downto 5))is
						when cmd_ROTONNSEOI	=>
							ROTONSEOI<='0';
						when cmd_SET_ROTAUTOEOI	=>
							ROTINAEOI<='1';
						when cmd_RES_ROTAUTOEOI =>
							ROTINAEOI<='0';
						when cmd_ROTONSEOI =>
							ROTONSEOI<='1';
						when others =>
						end case;
						S_LEV<=lDIN(2 downto 0);
					else
						RIS<=lDIN(0);
						RR<=lDIN(1);
						POLL<=lDIN(2);
						case lDIN(6 downto 5)is
						when "10" =>
							SMMODE<='0';
						when "11" =>
							SMMODE<='1';
						when others =>
						end case;
						SET_OC3<='1';
					end if;
				else
					case ICW is
					when 0 =>	--ICW2
						VECT<=lDIN(7 downto 3);
						if(SNGL='0')then
							ICW<=1;
						elsif(ICW4='0')then
							ICW<=3;
						else
							ICW<=2;
						end if;
					when 1 =>	--ICW3
						TOSLAVE<=lDIN;
						SLID<=lDIN(2 downto 0);
						if(ICW4='0')then
							ICW<=3;
						else
							ICW<=2;
						end if;
					when 2 =>	--ICW4
						AEOI<=lDIN(1);
--						AEOI<='1';
						M_Sn<=lDIN(2);
						BUF<=lDIN(3);
						SFNM<=lDIN(4);
						ICW<=3;
					when others =>
						IMR<=lDIN;
					end case;
				end if;
			end if;
		end if;
	end process;
	
	IRx<=IR7 & IR6 & IR5 & IR4 & IR3 & IR2 & IR1 & IR0;
	IRM<=IRx and (not IMR);
	
	process(clk,rstn)begin
		if(rstn='0')then
			IRL<=(others=>'0');
			lIRM<=(others=>'0');
			lIRx<=(others=>'0');
		elsif(clk' event and clk='1')then
			lIRM<=IRM;
			lIRx<=IRx;
			for i in 0 to 7 loop
				if(M_Sn='1' and TOSLAVE(i)='1')then
					IRL(i)<=IRM(i);
				else
--					if(lIRM(i)='0' and IRM(i)='1')then
--					if(IRM(i)='1')then
--					if(IRx(i)='1')then
					if(IRx(i)='1' and lIRx(i)='0')then
						IRL(i)<='1';
					end if;
					if(LCLR='1' and LCx=i)then
						IRL(i)<='0';
					end if;
--					if(IMR(i)='1')then
--						IRL(i)<='0';
--					end if;
				end if;
			end loop;
		end if;
	end process;
	
	IRR<=(IRL and (not IMR)) when L_En='0' else IRM;
	
	process(clk,rstn)
	variable vISnum	:integer range 0 to 15;
	begin
		if(rstn='0')then
			mISnum<=8;
		elsif(clk' event and clk='1')then
			if(ISnum=8)then
				mISnum<=8;
			else
				vISnum:=ISnum+PRI;
				if(vISnum>7)then
					mISnum<=vISnum-8;
				else
					mISnum<=vISnum;
				end if;
			end if;
		end if;
	end process;
	
	process(clk,rstn)
	variable INTv	:std_logic;
	begin
		if(rstn='0')then
			INTb<='0';
		elsif(clk' event and clk='1')then
			INTv:='0';
			for i in 0 to 7 loop
				if(i<mISnum)then
					INTv:=INTv or IRR(i);
				end if;
			end loop;
--			if((ISR=x"00" and lEOI=0) or SFNM='1')then
			if(ISR=x"00" and lEOI=0)then
				INTb<=INTv;
			else
				INTb<='0';
			end if;
		end if;
	end process;
	INT<=INTb;
	
	process(clk,rstn)
	variable selx	:integer range 0 to 15;
	variable sel	:integer range 0 to 7;
	begin
		if(rstn='0')then
			INTnum<=0;
		elsif(clk' event and clk='1')then
			INTnum<=0;
			for i in 7 downto 0 loop
				selx:=i+PRI;
				if(selx>7)then
					sel:=selx-8;
				else
					sel:=selx;
				end if;
				if(IRR(sel)='1')then
					INTnum<=sel;
				end if;
			end loop;
		end if;
	end process;

	IVECT(2 downto 0)<=conv_std_logic_vector(INTnum,3);
	IVECT(7 downto 3)<=VECT;
	
	process(clk,rstn)
	variable inum	:integer range 0 to 7;
	variable isel	:integer range 0 to 7;
	begin
		if(rstn='0')then
			lINTA<='0';
			LCLR<='0';
			LCx<=0;
			ISR<=(others=>'0');
			ISnum<=8;
			lEOI<=0;
		elsif(clk' event and clk='1')then
			LCLR<='0';
			lINTA<=INTAm;
			if(lEOI>0)then
				lEOI<=lEOI-1;
			end if;
			if(INTAm='1')then
				LCx<=INTnum;
				ISnum<=INTnum;
				ISR(INTnum)<='1';
			elsif(lINTA='1' and INTAm='0')then
				if(AEOI='1')then
					lEOI<=5;
				end if;
--					ISnum<=8;
--					if(SMMODE='1')then
--						ISR<=ISR and IMR;
--					else
--						ISR<=(others=>'0');
--					end if;
--					ISR(LCx)<='1';
--					LCLR<='1';
--				end if;
			elsif(command=cmd_NSEOI or command=cmd_SEOI or lEOI=3)then
				if(command=cmd_NSEOI or lEOI=1)then
					if(SMMODE='1')then
						ISR<=ISR and IMR;
					else
						ISR<=(others=>'0');
					end if;
				else
					isel:=conv_integer(S_LEV);
					ISR(isel)<='0';
				end if;
				lEOI<=2;
				LCLR<='1';
			elsif(lEOI=1)then
				if(INTb='1')then
					ISR(INTnum)<='1';
					ISnum<=INTnum;
					LCx<=INTnum;
				else
					ISnum<=8;
				end if;
			end if;
		end if;
	end process;
	
	CASO<=conv_std_logic_vector(INTnum,3);
	DOE<=	'1' when CS='1' and RD='1' else
			'1' when (INTA='1' and (M_Sn='1' and TOSLAVE(INTnum)='0')) else
			'1' when (INTA='1' and (M_Sn='0' and SLID=CASI)) else
			'0';
	DOUT<=	IVECT when INTA='1' else
			IMR	when ADDR='1' else
			ISR	when RR='1' and RIS='1' else
			IRR 	when RR='1' and RIS='0' else
			(others=>'0');

	process(clk,rstn)begin
		if(rstn='0')then
			PRI<=0;
		elsif(clk' event and clk='1')then
			if(command=CMD_SETPRIO)then
				PRI<=conv_integer(S_LEV);
			elsif(command=cmd_SEOI and ROTONSEOI='1')then
				PRI<=7-INTnum;
			elsif(command=cmd_NSEOI and ROTONSEOI='0')then
				PRI<=7-INTnum;
			elsif(ROTINAEOI='1' and lINTA='1' and INTAm='0')then
				PRI<=7-LCx;
			end if;
		end if;
	end process;

end rtl;