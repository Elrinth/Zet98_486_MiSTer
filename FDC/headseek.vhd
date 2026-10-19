LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity headseek is
generic(
	maxtrack	:integer	:=79;
	maxset		:integer	:=10;
	initseek	:integer	:=0
);
port(
	desttrack	:in integer range 0 to maxtrack;
	destset		:in std_logic;
	setwait		:in integer range 0 to maxset;		--settling time
	
	curtrack	:out integer range 0 to maxtrack;
	
	reachtrack	:out std_logic;
	busy		:out std_logic;
	
	track0		:in std_logic;
	seek		:out std_logic;
	sdir		:out std_logic;
	
	init		:in std_logic;
	seekerr		:out std_logic;
	
	sft			:in std_logic;
	clk			:in std_logic;
	rstn		:in std_logic
);
end headseek;

architecture rtl of headseek is
signal	current	:integer range 0 to maxtrack;

	type state_t is (
		ST_INIIN0,
		ST_INIIN1,
		ST_INIOUT,
		ST_IDLE,
		ST_CONTROL,
		ST_WAITSET,
		ST_NOP
	);
	signal	state	:state_t;
	
	type movestate_t is(
		MS_IDLE,
		MS_SETDIR,
		MS_DIRWAIT,
		MS_SEEKON,
		MS_SEEKOFF,
		MS_SEEKWAIT
	);
	signal	movestate	:movestate_t;
	

signal	movedir		:std_logic;
signal	move		:std_logic;
signal	intbusy		:std_logic;
signal	curdir		:std_logic;
signal	wsetcount	:integer range 0 to maxset;
signal	seekerrb	:std_logic;
signal	busyb		:std_logic;

begin

	process(clk,rstn)begin
		if(rstn='0')then
			current<=0;
			movedir<='1';
			move<='0';
			reachtrack<='0';
			seekerrb<='0';
			if(initseek=0)then
				busyb<='0';
				state<=ST_IDLE;
			else
				busyb<='1';
				state<=ST_INIIN0;
			end if;
		elsif(clk' event and clk='1')then
			reachtrack<='0';
			move<='0';
			if(init='1')then
				STATE<=ST_INIIN0;
				current<=0;
				seekerrb<='0';
				busyb<='1';
			end if;
			case state is
			when ST_INIIN0 =>
				if(intbusy='0')then
					if(track0='0')then
						if(current<maxtrack)then
							movedir<='0';
							move<='1';
							current<=current+1;
						else
							seekerrb<='1';
							busyb<='1';
							state<=ST_IDLE;
						end if;
					else
						current<=0;
						state<=st_INIIN1;
					end if;
				end if;
			when ST_INIIN1 =>
				if(intbusy='0')then
					if(current<1)then
						movedir<='0';
						move<='1';
						current<=current+1;
					else
						current<=maxtrack;
						state<=st_INIOUT;
					end if;
				end if;
			when ST_INIOUT =>
				if(intbusy='0')then
					if(track0='1')then
						if(current>0)then
							current<=current-1;
							movedir<='1';
							move<='1';
						else
							seekerrb<='1';
							busyb<='0';
							state<=ST_IDLE;
						end if;
					else
						current<=0;
						seekerrb<='0';
						wsetcount<=setwait;
						state<=ST_WAITSET;
					end if;
				end if;
			when ST_IDLE =>
				if(destset='1')then
					if(current=desttrack)then
						reachtrack<='1';
						state<=ST_NOP;
						busyb<='1';
					else
						if(desttrack>current)then
							movedir<='0';
						else
							movedir<='1';
						end if;
						state<=ST_CONTROL;
						busyb<='1';
					end if;
				end if;
			when ST_NOP =>
				busyb<='0';
				state<=st_IDLE;
			when ST_CONTROL =>
				if(intbusy='0')then
					if(current=desttrack)then
						wsetcount<=setwait;
						state<=ST_WAITSET;
					else
						move<='1';
						if(movedir='1')then
							current<=current-1;
						else
							current<=current+1;
						end if;
					end if;
				end if;
			when ST_WAITSET =>
				if(sft='1')then
					if(wsetcount>0)then
						wsetcount<=wsetcount-1;
					else
						reachtrack<='1';
						busyb<='0';
						state<=ST_IDLE;
					end if;
				end if;
			when others=>
				state<=ST_IDLE;
			end case;
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			seek<='1';
			curdir<='0';
			movestate<=MS_IDLE;
		elsif(clk' event and clk='1')then
			if(move='1')then
				if(curdir=movedir)then
					movestate<=MS_SEEKON;
				else
					movestate<=MS_SETDIR;
				end if;
			elsif(sft='1')then
				case movestate is
				when MS_SETDIR =>
					curdir<=movedir;
					movestate<=MS_DIRWAIT;
				when MS_DIRWAIT =>
					movestate<=MS_SEEKON;
				when MS_SEEKON =>
					seek<='0';
					movestate<=MS_SEEKOFF;
				when MS_SEEKOFF =>
					seek<='1';
					movestate<=MS_SEEKWAIT;
				when MS_SEEKWAIT =>
					movestate<=MS_IDLE;
				when others =>
					movestate<=MS_IDLE;
				end case;
			end if;
		end if;
	end process;
	
	intbusy<=	'1' when move='1' else
				'1' when movestate/=MS_IDLE else
				'0';

	sdir<=curdir;
	curtrack<=current;
	seekerr<=seekerrb and not (destset or init);
	busy<=	'1' when destset='1' else
				'1' when init='1' else
				busyb;
end rtl;
				
			
		
		



-- headseek4: the four units' head positioners on one stepping engine.
-- seekcont runs one seek/recalibrate at a time and waits for its end or
-- error, so only the per-unit results need their own registers: cylinder,
-- last step direction, busy and the equipment-check flag. Each operation
-- runs exactly as on a private headseek. A SEEK of a unit whose last
-- RECALIBRATE failed still ends at once with an equipment check, but the
-- engine no longer stalls mid-seek on it (the per-unit engines left that
-- unit busy, and the next SEEK of it hung the controller).
LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity headseek4 is
generic(
	maxtrack	:integer	:=79;
	maxset		:integer	:=10
);
port(
	dest0		:in integer range 0 to maxtrack;
	dest1		:in integer range 0 to maxtrack;
	dest2		:in integer range 0 to maxtrack;
	dest3		:in integer range 0 to maxtrack;
	destset		:in std_logic_vector(3 downto 0);	-- one-hot seek start
	init		:in std_logic_vector(3 downto 0);	-- one-hot recalibrate start
	setwait		:in integer range 0 to maxset;		--settling time
	usel		:in std_logic_vector(1 downto 0);	-- unit seekcont is serving

	cur0		:out integer range 0 to maxtrack;
	cur1		:out integer range 0 to maxtrack;
	cur2		:out integer range 0 to maxtrack;
	cur3		:out integer range 0 to maxtrack;

	reachtrack	:out std_logic_vector(3 downto 0);
	busy		:out std_logic_vector(3 downto 0);
	seekerr		:out std_logic_vector(3 downto 0);

	track0		:in std_logic;
	seek		:out std_logic;
	sdir		:out std_logic;

	sft			:in std_logic;
	clk			:in std_logic;
	rstn		:in std_logic
);
end headseek4;

architecture rtl of headseek4 is
	type cur_t is array(0 to 3) of integer range 0 to maxtrack;
	signal	current	:cur_t;
	signal	curdir	:std_logic_vector(3 downto 0);
	signal	busyb	:std_logic_vector(3 downto 0);
	signal	seekerrb:std_logic_vector(3 downto 0);

	type state_t is (
		ST_INIIN0,
		ST_INIIN1,
		ST_INIOUT,
		ST_IDLE,
		ST_CONTROL,
		ST_WAITSET,
		ST_NOP
	);
	signal	state	:state_t;

	type movestate_t is(
		MS_IDLE,
		MS_SETDIR,
		MS_DIRWAIT,
		MS_SEEKON,
		MS_SEEKOFF,
		MS_SEEKWAIT
	);
	signal	movestate	:movestate_t;

	signal	unit		:integer range 0 to 3;	-- unit of the running operation
	signal	movedir		:std_logic;
	signal	move		:std_logic;
	signal	intbusy		:std_logic;
	signal	wsetcount	:integer range 0 to maxset;
	signal	start		:std_logic_vector(3 downto 0);
	signal	su			:integer range 0 to 3;	-- unit this cycle
	signal	desttrack	:integer range 0 to maxtrack;
	signal	cur			:integer range 0 to maxtrack;
	signal	esft		:std_logic;
	signal	reach		:std_logic;
begin
	start<=destset or init;
	su<=	0 when start(0)='1' else
			1 when start(1)='1' else
			2 when start(2)='1' else
			3 when start(3)='1' else
			unit;
	desttrack<=	dest0 when su=0 else
				dest1 when su=1 else
				dest2 when su=2 else
				dest3;
	cur<=current(su);
	-- each private engine only saw step ticks while seekcont served its unit
	esft<=sft when conv_integer(usel)=unit else '0';

	process(clk,rstn)begin
		if(rstn='0')then
			current<=(others=>0);
			busyb<=(others=>'0');
			seekerrb<=(others=>'0');
			unit<=0;
			movedir<='1';
			move<='0';
			reach<='0';
			state<=ST_IDLE;
		elsif(clk' event and clk='1')then
			reach<='0';
			move<='0';
			if(start/="0000")then
				unit<=su;
			end if;
			if(init(su)='1')then
				state<=ST_INIIN0;
				current(su)<=0;
				seekerrb(su)<='0';
				busyb(su)<='1';
			end if;
			case state is
			when ST_INIIN0 =>
				if(intbusy='0')then
					if(track0='0')then
						if(cur<maxtrack)then
							movedir<='0';
							move<='1';
							current(su)<=cur+1;
						else
							seekerrb(su)<='1';
							busyb(su)<='1';
							state<=ST_IDLE;
						end if;
					else
						current(su)<=0;
						state<=st_INIIN1;
					end if;
				end if;
			when ST_INIIN1 =>
				if(intbusy='0')then
					if(cur<1)then
						movedir<='0';
						move<='1';
						current(su)<=cur+1;
					else
						current(su)<=maxtrack;
						state<=st_INIOUT;
					end if;
				end if;
			when ST_INIOUT =>
				if(intbusy='0')then
					if(track0='1')then
						if(cur>0)then
							current(su)<=cur-1;
							movedir<='1';
							move<='1';
						else
							seekerrb(su)<='1';
							busyb(su)<='0';
							state<=ST_IDLE;
						end if;
					else
						current(su)<=0;
						seekerrb(su)<='0';
						wsetcount<=setwait;
						state<=ST_WAITSET;
					end if;
				end if;
			when ST_IDLE =>
				if(destset(su)='1' and seekerrb(su)='1')then
					-- unit failed its last recalibrate: equipment check again
					-- at once, as the per-unit engines did (it keeps Windows'
					-- floppy driver from taking driveless units 2/3 as drives)
					null;
				elsif(destset(su)='1')then
					if(cur=desttrack)then
						reach<='1';
						state<=ST_NOP;
						busyb(su)<='1';
					else
						if(desttrack>cur)then
							movedir<='0';
						else
							movedir<='1';
						end if;
						state<=ST_CONTROL;
						busyb(su)<='1';
					end if;
				end if;
			when ST_NOP =>
				busyb(su)<='0';
				state<=st_IDLE;
			when ST_CONTROL =>
				if(intbusy='0')then
					if(cur=desttrack)then
						wsetcount<=setwait;
						state<=ST_WAITSET;
					else
						move<='1';
						if(movedir='1')then
							current(su)<=cur-1;
						else
							current(su)<=cur+1;
						end if;
					end if;
				end if;
			when ST_WAITSET =>
				if(esft='1')then
					if(wsetcount>0)then
						wsetcount<=wsetcount-1;
					else
						reach<='1';
						busyb(su)<='0';
						state<=ST_IDLE;
					end if;
				end if;
			when others=>
				state<=ST_IDLE;
			end case;
		end if;
	end process;

	process(clk,rstn)begin
		if(rstn='0')then
			seek<='1';
			curdir<=(others=>'0');
			movestate<=MS_IDLE;
		elsif(clk' event and clk='1')then
			if(move='1')then
				if(curdir(unit)=movedir)then
					movestate<=MS_SEEKON;
				else
					movestate<=MS_SETDIR;
				end if;
			elsif(esft='1')then
				case movestate is
				when MS_SETDIR =>
					curdir(unit)<=movedir;
					movestate<=MS_DIRWAIT;
				when MS_DIRWAIT =>
					movestate<=MS_SEEKON;
				when MS_SEEKON =>
					seek<='0';
					movestate<=MS_SEEKOFF;
				when MS_SEEKOFF =>
					seek<='1';
					movestate<=MS_SEEKWAIT;
				when MS_SEEKWAIT =>
					movestate<=MS_IDLE;
				when others =>
					movestate<=MS_IDLE;
				end case;
			end if;
		end if;
	end process;

	intbusy<=	'1' when move='1' else
				'1' when movestate/=MS_IDLE else
				'0';

	sdir<=curdir(conv_integer(usel));
	cur0<=current(0);
	cur1<=current(1);
	cur2<=current(2);
	cur3<=current(3);
	reachtrack<=	"0001" when reach='1' and unit=0 else
					"0010" when reach='1' and unit=1 else
					"0100" when reach='1' and unit=2 else
					"1000" when reach='1' and unit=3 else
					"0000";
	seekerr<=seekerrb and not start;
	busy<=busyb or start;
end rtl;
