-- Behavioural stand-ins for the diskemu_mister altsyncram wrappers, with the
-- same registered-address / output-register latencies as the megafunctions:
--   sectram : address registered on clock, output unregistered (1 cycle)
--   fecbuf  : port A as sectram; port B address and output registered (2 cycles)
--   sramram : as sectram (only compiled, the SRAM slot is never mounted here)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sectram is
    port(address_a, address_b : in std_logic_vector(8 downto 0);
         clock : in std_logic := '1';
         data_a, data_b : in std_logic_vector(7 downto 0);
         wren_a, wren_b : in std_logic := '0';
         q_a, q_b : out std_logic_vector(7 downto 0));
end entity;
architecture model of sectram is
begin
    process(clock)
        type mem_t is array(0 to 511) of std_logic_vector(7 downto 0);
        variable mem : mem_t := (others=>(others=>'0'));
        variable ra, rb : natural range 0 to 511 := 0;
    begin
        if rising_edge(clock) then
            if wren_a='1' then mem(to_integer(unsigned(address_a))) := data_a; end if;
            if wren_b='1' then mem(to_integer(unsigned(address_b))) := data_b; end if;
            ra := to_integer(unsigned(address_a));
            rb := to_integer(unsigned(address_b));
            q_a <= mem(ra);
            q_b <= mem(rb);
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fecbuf is
    port(address_a, address_b : in std_logic_vector(7 downto 0);
         clock_a : in std_logic := '1';
         clock_b : in std_logic;
         data_a, data_b : in std_logic_vector(15 downto 0);
         wren_a, wren_b : in std_logic := '0';
         q_a, q_b : out std_logic_vector(15 downto 0));
end entity;
architecture model of fecbuf is
begin
    process(clock_a, clock_b)
        type mem_t is array(0 to 255) of std_logic_vector(15 downto 0);
        variable mem : mem_t := (others=>(others=>'0'));
        variable ra, rb : natural range 0 to 255 := 0;
    begin
        if rising_edge(clock_b) then
            q_b <= mem(rb);                     -- output register (CLOCK1)
            if wren_b='1' then mem(to_integer(unsigned(address_b))) := data_b; end if;
            rb := to_integer(unsigned(address_b));
        end if;
        if rising_edge(clock_a) then
            if wren_a='1' then mem(to_integer(unsigned(address_a))) := data_a; end if;
            ra := to_integer(unsigned(address_a));
        end if;
        q_a <= mem(ra);                         -- unregistered output
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sramram is
    port(address_a : in std_logic_vector(12 downto 0);
         address_b : in std_logic_vector(13 downto 0);
         byteena_a : in std_logic_vector(1 downto 0) := (others=>'1');
         clock : in std_logic := '1';
         data_a : in std_logic_vector(15 downto 0);
         data_b : in std_logic_vector(7 downto 0);
         wren_a, wren_b : in std_logic := '0';
         q_a : out std_logic_vector(15 downto 0);
         q_b : out std_logic_vector(7 downto 0));
end entity;
architecture model of sramram is
begin
    process(clock)
        type mem_t is array(0 to 16383) of std_logic_vector(7 downto 0);
        variable mem : mem_t := (others=>(others=>'0'));
        variable a : natural;
    begin
        if rising_edge(clock) then
            a := 2*to_integer(unsigned(address_a));
            if wren_a='1' then
                if byteena_a(0)='1' then mem(a) := data_a(7 downto 0); end if;
                if byteena_a(1)='1' then mem(a+1) := data_a(15 downto 8); end if;
            end if;
            if wren_b='1' then mem(to_integer(unsigned(address_b))) := data_b; end if;
            q_a <= mem(a+1) & mem(a);
            q_b <= mem(to_integer(unsigned(address_b)));
        end if;
    end process;
end architecture;
