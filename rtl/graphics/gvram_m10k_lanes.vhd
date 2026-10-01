-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

-- Graphics VRAM block RAM: 32K x 64 bits with byte enables on port A
-- (CPU clock, read/write) and a read-only port B (pixel clock). Built from
-- 8K x 1 M10K blocks (256 blocks), so each output needs only a 4:1 depth
-- multiplexer. Both ports register the address; outputs are unregistered.
-- tests/gvram_m10k_lanes_sim.vhd is the simulation model of this entity.
entity gvram_m10k_lanes is
port(
    clk_a  : in std_logic;
    addr_a : in std_logic_vector(14 downto 0);
    we_a   : in std_logic_vector(7 downto 0);
    d_a    : in std_logic_vector(63 downto 0);
    q_a    : out std_logic_vector(63 downto 0);
    clk_b  : in std_logic;
    addr_b : in std_logic_vector(14 downto 0);
    q_b    : out std_logic_vector(63 downto 0)
);
end gvram_m10k_lanes;

architecture syn of gvram_m10k_lanes is
    signal wren : std_logic;
begin
    wren <= '1' when we_a/="00000000" else '0';
    ram : altsyncram
    generic map(
        address_reg_b => "CLOCK1",
        clock_enable_input_a => "BYPASS",
        clock_enable_input_b => "BYPASS",
        clock_enable_output_a => "BYPASS",
        clock_enable_output_b => "BYPASS",
        indata_reg_b => "CLOCK1",
        intended_device_family => "Cyclone V",
        lpm_type => "altsyncram",
        maximum_depth => 8192,
        numwords_a => 32768,
        numwords_b => 32768,
        operation_mode => "BIDIR_DUAL_PORT",
        outdata_aclr_a => "NONE",
        outdata_aclr_b => "NONE",
        outdata_reg_a => "UNREGISTERED",
        outdata_reg_b => "UNREGISTERED",
        power_up_uninitialized => "FALSE",
        ram_block_type => "M10K",
        read_during_write_mode_mixed_ports => "DONT_CARE",
        read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
        read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
        widthad_a => 15,
        widthad_b => 15,
        width_a => 64,
        width_b => 64,
        width_byteena_a => 8,
        width_byteena_b => 1,
        wrcontrol_wraddress_reg_b => "CLOCK1"
    )
    port map(
        clock0 => clk_a,
        address_a => addr_a,
        data_a => d_a,
        wren_a => wren,
        byteena_a => we_a,
        q_a => q_a,
        clock1 => clk_b,
        address_b => addr_b,
        data_b => (others=>'0'),
        wren_b => '0',
        q_b => q_b
    );
end syn;
