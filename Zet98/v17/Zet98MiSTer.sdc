derive_pll_clocks

# core specific constraints
source [file join [file dirname [info script]] pc98-pixel.sdc]
source [file join [file dirname [info script]] pc98-graphics-transfer.sdc]
derive_clock_uncertainty
