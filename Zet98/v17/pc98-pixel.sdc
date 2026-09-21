# VTIMING rotates 001 on the 75 MHz video clock. Its clk3sft[2] output
# clocks the 25 MHz raster/text logic, with one parent cycle high. Include
# this clock during fitting, not only in an after-the-fact timing audit.
set pixel_register [get_registers {*|VID|TIM|clk3sft[2]}]
set pixel_source [get_pins -compatibility_mode {*|VID|TIM|clk3sft[2]|clk}]
if {[get_collection_size $pixel_register] != 1 || [get_collection_size $pixel_source] != 1} {
    error "Expected one VTIMING pixel divider register and clock pin"
}
# Reset release can select any of three phases against the other PLL clocks.
# They describe alternative phases of the same physical clock, never clocks
# that operate simultaneously. Do not exclude their paths to other clocks.
create_generated_clock -name pc98_pixel_phase0 -source $pixel_source -edges {1 3 7} $pixel_register
create_generated_clock -name pc98_pixel_phase1 -source $pixel_source -edges {3 5 9} -add $pixel_register
create_generated_clock -name pc98_pixel_phase2 -source $pixel_source -edges {5 7 11} -add $pixel_register
set_clock_groups -logically_exclusive -group {pc98_pixel_phase0} -group {pc98_pixel_phase1} -group {pc98_pixel_phase2}
