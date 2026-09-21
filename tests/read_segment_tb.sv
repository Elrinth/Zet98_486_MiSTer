`timescale 1ns/1ps
module read_segment_tb;
reg [63:0] es_cache;
reg [63:0] cs_cache;
reg [63:0] ss_cache;
reg [63:0] ds_cache;
reg [63:0] fs_cache;
reg [63:0] gs_cache;
reg [63:0] tr_cache;
reg [63:0] ldtr_cache;
reg  es_cache_valid;
reg  cs_cache_valid;
reg  ss_cache_valid;
reg  ds_cache_valid;
reg  fs_cache_valid;
reg  gs_cache_valid;
reg  address_stack_pop;
reg  address_stack_pop_next;
reg  address_enter_last;
reg  address_enter;
reg  address_leave;
reg  address_edi;
reg  read_virtual;
reg  read_rmw_virtual;
reg  write_virtual_check;
reg [31:0] rd_address_effective;
reg  rd_address_effective_ready;
reg [3:0] read_length;
reg [2:0] rd_prefix_group_2_seg;
wire [31:0] tr_base, ref_tr_base;
wire [31:0] ldtr_base, ref_ldtr_base;
wire [31:0] tr_limit, ref_tr_limit;
wire [31:0] ldtr_limit, ref_ldtr_limit;
wire  rd_seg_gp_fault_init, ref_rd_seg_gp_fault_init;
wire  rd_seg_ss_fault_init, ref_rd_seg_ss_fault_init;
wire [31:0] rd_seg_linear, ref_rd_seg_linear;
read_segment dut(.es_cache(es_cache),
    .cs_cache(cs_cache),
    .ss_cache(ss_cache),
    .ds_cache(ds_cache),
    .fs_cache(fs_cache),
    .gs_cache(gs_cache),
    .tr_cache(tr_cache),
    .ldtr_cache(ldtr_cache),
    .es_cache_valid(es_cache_valid),
    .cs_cache_valid(cs_cache_valid),
    .ss_cache_valid(ss_cache_valid),
    .ds_cache_valid(ds_cache_valid),
    .fs_cache_valid(fs_cache_valid),
    .gs_cache_valid(gs_cache_valid),
    .address_stack_pop(address_stack_pop),
    .address_stack_pop_next(address_stack_pop_next),
    .address_enter_last(address_enter_last),
    .address_enter(address_enter),
    .address_leave(address_leave),
    .address_edi(address_edi),
    .read_virtual(read_virtual),
    .read_rmw_virtual(read_rmw_virtual),
    .write_virtual_check(write_virtual_check),
    .rd_address_effective(rd_address_effective),
    .rd_address_effective_ready(rd_address_effective_ready),
    .read_length(read_length),
    .rd_prefix_group_2_seg(rd_prefix_group_2_seg),
    .tr_base(tr_base),
    .ldtr_base(ldtr_base),
    .tr_limit(tr_limit),
    .ldtr_limit(ldtr_limit),
    .rd_seg_gp_fault_init(rd_seg_gp_fault_init),
    .rd_seg_ss_fault_init(rd_seg_ss_fault_init),
    .rd_seg_linear(rd_seg_linear));
read_segment_legacy reference(.es_cache(es_cache),
    .cs_cache(cs_cache),
    .ss_cache(ss_cache),
    .ds_cache(ds_cache),
    .fs_cache(fs_cache),
    .gs_cache(gs_cache),
    .tr_cache(tr_cache),
    .ldtr_cache(ldtr_cache),
    .es_cache_valid(es_cache_valid),
    .cs_cache_valid(cs_cache_valid),
    .ss_cache_valid(ss_cache_valid),
    .ds_cache_valid(ds_cache_valid),
    .fs_cache_valid(fs_cache_valid),
    .gs_cache_valid(gs_cache_valid),
    .address_stack_pop(address_stack_pop),
    .address_stack_pop_next(address_stack_pop_next),
    .address_enter_last(address_enter_last),
    .address_enter(address_enter),
    .address_leave(address_leave),
    .address_edi(address_edi),
    .read_virtual(read_virtual),
    .read_rmw_virtual(read_rmw_virtual),
    .write_virtual_check(write_virtual_check),
    .rd_address_effective(rd_address_effective),
    .rd_address_effective_ready(rd_address_effective_ready),
    .read_length(read_length),
    .rd_prefix_group_2_seg(rd_prefix_group_2_seg),
    .tr_base(ref_tr_base),
    .ldtr_base(ref_ldtr_base),
    .tr_limit(ref_tr_limit),
    .ldtr_limit(ref_ldtr_limit),
    .rd_seg_gp_fault_init(ref_rd_seg_gp_fault_init),
    .rd_seg_ss_fault_init(ref_rd_seg_ss_fault_init),
    .rd_seg_linear(ref_rd_seg_linear));
integer checks=0;
integer seed=32'h981486;
integer i,j,len,sel,delta,kind,control,rotation;
reg [63:0] descriptors[0:7];
reg [31:0] limits[0:7];
reg [31:0] boundary;
task check;
    begin
        #1;
        if (tr_base !== ref_tr_base) $fatal(1,"segment differs: tr_base case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (ldtr_base !== ref_ldtr_base) $fatal(1,"segment differs: ldtr_base case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (tr_limit !== ref_tr_limit) $fatal(1,"segment differs: tr_limit case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (ldtr_limit !== ref_ldtr_limit) $fatal(1,"segment differs: ldtr_limit case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (rd_seg_gp_fault_init !== ref_rd_seg_gp_fault_init) $fatal(1,"segment differs: rd_seg_gp_fault_init case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (rd_seg_ss_fault_init !== ref_rd_seg_ss_fault_init) $fatal(1,"segment differs: rd_seg_ss_fault_init case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        if (rd_seg_linear !== ref_rd_seg_linear) $fatal(1,"segment differs: rd_seg_linear case=%0d select=%0d address=%h length=%0d", checks, dut.seg_select, rd_address_effective,read_length);
        checks=checks+1;
    end
endtask
task random_inputs;
    begin
        es_cache = {$random(seed),$random(seed)};
        cs_cache = {$random(seed),$random(seed)};
        ss_cache = {$random(seed),$random(seed)};
        ds_cache = {$random(seed),$random(seed)};
        fs_cache = {$random(seed),$random(seed)};
        gs_cache = {$random(seed),$random(seed)};
        tr_cache = {$random(seed),$random(seed)};
        ldtr_cache = {$random(seed),$random(seed)};
        es_cache_valid = $random(seed);
        cs_cache_valid = $random(seed);
        ss_cache_valid = $random(seed);
        ds_cache_valid = $random(seed);
        fs_cache_valid = $random(seed);
        gs_cache_valid = $random(seed);
        address_stack_pop = $random(seed);
        address_stack_pop_next = $random(seed);
        address_enter_last = $random(seed);
        address_enter = $random(seed);
        address_leave = $random(seed);
        address_edi = $random(seed);
        read_virtual = $random(seed);
        read_rmw_virtual = $random(seed);
        write_virtual_check = $random(seed);
        rd_address_effective = $random(seed);
        rd_address_effective_ready = $random(seed);
        read_length = $random(seed);
        rd_prefix_group_2_seg = $random(seed);
    end
endtask
initial begin
    // Invalid/code/data/expand-down descriptors, G/DB, all selectors and
    // stack overrides are covered with independent randomized inputs.
    for(i=0;i<50000;i=i+1) begin random_inputs; check; end
    limits[0]=0; limits[1]=14; limits[2]=15; limits[3]=16;
    limits[4]=32'hfff; limits[5]=32'hffff;
    limits[6]=32'hfffff; limits[7]=32'hffffffff;
    for(rotation=0;rotation<8;rotation=rotation+1)
    for(kind=0;kind<32;kind=kind+1) begin
        random_inputs;
        address_stack_pop=0; address_stack_pop_next=0;
        address_enter_last=0; address_enter=0; address_leave=0; address_edi=0;
        es_cache_valid=1; cs_cache_valid=1; ss_cache_valid=1;
        ds_cache_valid=1; fs_cache_valid=1; gs_cache_valid=1;
        rd_address_effective_ready=1;
        for(j=0;j<8;j=j+1) begin
            descriptors[j]=0;
            descriptors[j][15:0]=limits[(j+rotation)%8][15:0];
            descriptors[j][51:48]=limits[(j+rotation)%8][19:16];
            descriptors[j][43:41]=kind[2:0];
            descriptors[j][54]=kind[3]; descriptors[j][55]=kind[4];
            descriptors[j][47]=1;
            descriptors[j][39:16]=24'h123456+j;
        end
        es_cache=descriptors[0]; cs_cache=descriptors[1]; ss_cache=descriptors[2];
        ds_cache=descriptors[3]; fs_cache=descriptors[4]; gs_cache=descriptors[5];
        for(sel=0;sel<8;sel=sel+1) begin
            rd_prefix_group_2_seg=sel; #1;
            case(sel)
              0:boundary=dut.es_limit; 1:boundary=dut.cs_limit;
              2:boundary=dut.ss_limit; 3:boundary=dut.ds_limit;
              4:boundary=dut.fs_limit; default:boundary=dut.gs_limit;
            endcase
            for(delta=-17;delta<=17;delta=delta+1)
              for(len=0;len<16;len=len+1)
                for(control=0;control<4;control=control+1) begin
                    rd_address_effective=boundary+delta;
                    read_length=len;
                    read_virtual=control[0]; write_virtual_check=control[1];
                    read_rmw_virtual=0;
                    check;
                end
        end
    end
    $display("PASS: segment access equivalence %0d cases",checks);
    $finish;
end
endmodule
