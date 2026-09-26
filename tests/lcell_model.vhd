-- Functional model of Quartus LCELL, for GHDL tests only. No silicon delay
-- is assumed here; transport-budget tests inject the full constrained bound.
library ieee;
use ieee.std_logic_1164.all;
entity LCELL is
    port (a_in : in std_logic; a_out : out std_logic);
end entity;
architecture functional of LCELL is begin
    a_out <= a_in;
end architecture;
