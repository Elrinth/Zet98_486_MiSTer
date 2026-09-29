derive_pll_clocks
set pegc_enabled 0

# core specific constraints
source [file join [file dirname [info script]] pc98-pixel.sdc]
source [file join [file dirname [info script]] pc98-graphics-transfer.sdc]
source [file join [file dirname [info script]] pc98-display-page.sdc]
source [file join [file dirname [info script]] pc98-palette-transfer.sdc]
source [file join [file dirname [info script]] pc98-video-settings.sdc]
if {$pegc_enabled} {source [file join [file dirname [info script]] pc98-pegc-transfer.sdc]}
source [file join [file dirname [info script]] pc98-scaler-settings.sdc]
source [file join [file dirname [info script]] pc98-video-reset.sdc]
source [file join [file dirname [info script]] pc98-cpu-write-transfer.sdc]
source [file join [file dirname [info script]] pc98-read-transfer.sdc]
source [file join [file dirname [info script]] pc98-sdram-control.sdc]
source [file join [file dirname [info script]] pc98-host-video-settings.sdc]
source [file join [file dirname [info script]] pc98-video-status.sdc]
source [file join [file dirname [info script]] pc98-host-io.sdc]
source [file join [file dirname [info script]] pc98-posted-write.sdc]

derive_clock_uncertainty
