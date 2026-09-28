# sys_top host-command receiver (HPS gp_out words -> HDMI timing, scaler,
# framebuffer, audio filter, aspect and OSD-adjacent settings). It runs on
# the core clk_sys but every register below updates only on sys_top io_ce,
# which toggles each clk_sys cycle, so launches and captures are two clk_sys
# periods apart. The one-cycle coef_wr/shadowmask_wr pulses are cleared on
# every edge; they are only captures here, never launches. io_ce itself, the
# gp_outd synchronizer stage, io_wait, hdmi_vs_sync and every consumer outside
# this set remain single-cycle timed.
set host_io_launch [get_registers -nowarn {
    gp_outr[*] rack io_ack old_strobe cmd[*] has_cmd cnt[*] acx_att[*]
    vs_d0 vs_d1 vs_d2 vs_wait vs_line[*]
    WIDTH[*] HFP[*] HS[*] HBP[*] HEIGHT[*] VFP[*] VS[*] VBP[*]
    cfg[*] cfg_set scaler_out cfg_custom_t cfg_custom_p1[*] cfg_custom_p2[*]
    lowlat cfg_dis LFB_EN LFB_FLT LFB_FMT[*] LFB_BASE[*] LFB_WIDTH[*]
    LFB_HEIGHT[*] LFB_HMIN[*] LFB_HMAX[*] LFB_VMIN[*] LFB_VMAX[*] LFB_STRIDE[*]
    led_overtake[*] led_state[*] vol_att[*] VSET[*] HSET[*] FREESCALE
    scaler_flt[*] aflt_rate[*] acx[*] acx0[*] acx1[*] acx2[*]
    acy0[*] acy1[*] acy2[*] areset arc1x[*] arc1y[*] arc2x[*] arc2y[*]
    coef_addr[*] coef_data[*] shadowmask_data[*]
}]
set host_io_capture [add_to_collection $host_io_launch [get_registers -nowarn {coef_wr shadowmask_wr}]]
foreach required {rack cmd[*] cnt[*] HEIGHT[*] WIDTH[*] VSET[*] gp_outr[17]} {
    if {[get_collection_size [get_registers -nowarn $required]] < 1} {
        error "Missing host-command receiver register: $required"
    }
}
post_message "Host command receiver: [get_collection_size $host_io_launch] half-rate launch, [get_collection_size $host_io_capture] capture registers"
set_multicycle_path -setup 2 -from $host_io_launch -to $host_io_capture
set_multicycle_path -hold 1 -from $host_io_launch -to $host_io_capture
# gp_outr changes only on io_ce edges, and io_strobe_bus (the one-cycle strobe
# given to hps_io and both OSDs) is high only in the second cycle after such a
# change, so the host data/select word has two clk_sys periods to reach them.
# The strobe's rack/io_ce terms stay single-cycle timed.
set host_bus_word [get_registers {gp_outr[*]}]
set host_bus_users [get_registers -nowarn {emu|hps_io|* vga_osd|* hdmi_osd|*}]
if {[get_collection_size $host_bus_users] < 1} {
    error "Missing hps_io/OSD host bus registers"
}
set_multicycle_path -setup 2 -from $host_bus_word -to $host_bus_users
set_multicycle_path -hold 1 -from $host_bus_word -to $host_bus_users
