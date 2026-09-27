// z486 PC-98 memory-map preset; splice `Z486_PC98_MAP_PARAMS into a `z486
// parameter list. VGA_BASE/VGA_TOP default to A0000-BFFFF. The no-allocate
// bound defaults to the 128 MiB L1 tag reach; use
// `Z486_PC98_MAP_PARAMS_BOUND(bound) to pass a lower bound, such as the RAM top.
`ifndef Z486_PC98_PRESET_SVH
`define Z486_PC98_PRESET_SVH

`define Z486_PC98_NO_ALLOC_BOUND 32'h0800_0000

`define Z486_PC98_MAP_PARAMS_BOUND(bound) \
    .A20_MASK_OFF    (32'h000f_ffff), \
    .VGA_ENABLE      (1'b1), \
    .VGA_PRE_WRAP    (1'b0), \
    .APERTURE_ENABLE (1'b1), \
    .ALIAS_ENABLE    (1'b1), \
    .WIN0_ENABLE     (1'b1), \
    .NO_ALLOC_ENABLE (1'b1), \
    .NO_ALLOC_BOUND  (bound)

`define Z486_PC98_MAP_PARAMS `Z486_PC98_MAP_PARAMS_BOUND(`Z486_PC98_NO_ALLOC_BOUND)

`endif
