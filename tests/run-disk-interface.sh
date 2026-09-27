#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
wrapper=${1:-Zet98/MiSTer/Zet98.sv}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
printf '`define BUILD_DATE "test"\n' > "$out/build_id.v"
# Icarus requires a default for untyped parameters. Both instances override
# CONF_STR/STRLEN; unused defaults in this temporary copy change no logic.
sed -e 's/parameter CONF_STR, STRLEN)/parameter CONF_STR = "", STRLEN = 1)/' \
    -e 's/parameter CONF_STR,/parameter CONF_STR = "",/' MiSTer/sys/hps_io.sv > "$out/hps_io.sv"
iverilog -g2012 -Wall -I "$out" -s mister_disk_interface_tb -o "$out/disk.vvp" \
    "$out/hps_io.sv" MiSTer/sys/math.sv MiSTer/sys/video_freak.sv rtl/video_output.sv rtl/boot_media_control.sv rtl/video_config_snapshot.sv rtl/pc98_video_scale.sv rtl/floppy_overlay.sv rtl/audio_decimator.sv rtl/snac_psx_pad.sv rtl/stick_mouse.sv rtl/pc98_artic.sv rtl/storage/pc98_image_bridge.sv rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv "$wrapper" tests/mister_disk_interface_tb.sv
vvp "$out/disk.vvp"
iverilog -g2012 -Wall -DZET98_RAW_IDE -I "$out" -s mister_ide_interface_tb -o "$out/ide.vvp" \
    "$out/hps_io.sv" MiSTer/sys/math.sv MiSTer/sys/video_freak.sv rtl/video_output.sv rtl/boot_media_control.sv rtl/video_config_snapshot.sv rtl/pc98_video_scale.sv rtl/floppy_overlay.sv rtl/audio_decimator.sv rtl/snac_psx_pad.sv rtl/stick_mouse.sv rtl/pc98_artic.sv rtl/storage/pc98_ide.sv rtl/storage/pc98_atapi.sv \
    rtl/storage/pc98_image_bridge.sv rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv "$wrapper" tests/mister_disk_interface_tb.sv tests/mister_ide_interface_tb.sv
vvp "$out/ide.vvp"
iverilog -g2012 -DZET98_RAW_IDE -I "$out" -s mister_ide_interface_tb -Pmister_ide_interface_tb.NATIVE=1 -o "$out/hdi.vvp" \
    "$out/hps_io.sv" MiSTer/sys/math.sv MiSTer/sys/video_freak.sv rtl/video_output.sv rtl/boot_media_control.sv rtl/video_config_snapshot.sv rtl/pc98_video_scale.sv rtl/floppy_overlay.sv rtl/audio_decimator.sv rtl/snac_psx_pad.sv rtl/stick_mouse.sv rtl/pc98_artic.sv rtl/storage/pc98_ide.sv rtl/storage/pc98_atapi.sv \
    rtl/storage/pc98_image_bridge.sv rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv "$wrapper" tests/mister_disk_interface_tb.sv tests/mister_ide_interface_tb.sv
vvp "$out/hdi.vvp"
iverilog -g2012 -Wall -DZET98_RAW_IDE -DZET98_MPU_UART -I "$out" -s mister_mpu_interface_tb -o "$out/mpu.vvp" \
    "$out/hps_io.sv" MiSTer/sys/math.sv MiSTer/sys/video_freak.sv rtl/video_output.sv rtl/boot_media_control.sv rtl/video_config_snapshot.sv rtl/pc98_video_scale.sv rtl/floppy_overlay.sv rtl/audio_decimator.sv rtl/snac_psx_pad.sv rtl/stick_mouse.sv rtl/pc98_artic.sv \
    rtl/storage/pc98_ide.sv rtl/storage/pc98_atapi.sv rtl/midi/pc98_mpu_uart.sv \
    rtl/storage/pc98_image_bridge.sv rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv "$wrapper" tests/mister_disk_interface_tb.sv tests/mister_mpu_interface_tb.sv
vvp "$out/mpu.vvp"
