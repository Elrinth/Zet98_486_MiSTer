derive_pll_clocks

# core specific constraints
source [file join [file dirname [info script]] pc98-pixel.sdc]
source [file join [file dirname [info script]] pc98-graphics-transfer.sdc]
source [file join [file dirname [info script]] pc98-palette-transfer.sdc]
source [file join [file dirname [info script]] pc98-video-reset.sdc]
source [file join [file dirname [info script]] pc98-cpu-write-transfer.sdc]
source [file join [file dirname [info script]] pc98-read-transfer.sdc]
derive_clock_uncertainty
