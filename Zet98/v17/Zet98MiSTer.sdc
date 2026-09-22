derive_pll_clocks

# core specific constraints
source [file join [file dirname [info script]] pc98-pixel.sdc]
source [file join [file dirname [info script]] pc98-graphics-transfer.sdc]
source [file join [file dirname [info script]] pc98-display-page.sdc]
source [file join [file dirname [info script]] pc98-palette-transfer.sdc]
source [file join [file dirname [info script]] pc98-video-settings.sdc]
source [file join [file dirname [info script]] pc98-scaler-settings.sdc]
source [file join [file dirname [info script]] pc98-video-reset.sdc]
source [file join [file dirname [info script]] pc98-cpu-write-transfer.sdc]
source [file join [file dirname [info script]] pc98-read-transfer.sdc]
source [file join [file dirname [info script]] pc98-host-video-settings.sdc]

derive_clock_uncertainty
