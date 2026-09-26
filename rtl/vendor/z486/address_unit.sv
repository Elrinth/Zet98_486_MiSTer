// Owns the architectural address registers and their relocated linear form.
// D2 supplies an effective address; segmentation supplies the active base/mask.
`include "z486_platform.svh"
module address_unit
    import z486_pkg::*;
#(
    parameter REGISTERED_EA = 0
)
(
    input  logic        clk,
    input  logic        reset_n,
    input  logic        instr_issue,           // Latch the next architectural address
    input  dec_entry_t  instr,
    input  logic        d2_start,            // Latch D2 base/index selection
    input  ea_dec_t     d2_ea,               // Predecoded D2 address recipe
    input  logic        split_ea_prepare,     // Capture base + scaled index
    input  logic        split_ea_use,         // Finish a three-term EA in D2b
    input  logic [2:0]  split_ea_adjust,      // Post-POP ESP correction in D2a
    input  logic [31:0] displacement,
    output gpr_ref_t    ea_base,             // GPR read request to data unit
    output gpr_ref_t    ea_index,            // Second GPR read request to data unit
    input  logic [31:0] ea_base_value,
    input  logic [31:0] ea_index_value,
    input  logic        branch_relative,     // EA is a relative branch target
    input  logic [31:0] branch_target_eip,   // D2-computed relative target
    input  logic [31:0] forwarded_esp,       // ESP including prior delay-slot write
    input  logic        ss_stack32,
    input  logic [31:0] issue_seg_base,      // D2 segment base, independent of seg command feedback
    input  logic        issue_eff_mask,      // D2 address mask, independent of seg command feedback

    input  logic        exec,                // Execute a microcode IND operation
    input  logic        exec_addr32,
    input  logic [5:0]  alu_source,
    input  logic [8:0]  ind_ctrl,            // Registered compact IND controls
    input  logic [31:0] source_value,
    input  logic [31:0] alu_value,
    input  logic [31:0] alu_value_hold,
    input  logic        instr_jcc,
    input  logic        pe,
    input  logic        is_dword,
    input  logic        descsw_mode,
    input  logic        cs_stack32,

    input  logic [3:0]  seg_cmd,             // Segment command paired with this cycle
    input  logic [3:0]  seg_sel,             // Segment selected by segmentation unit
    input  logic [31:0] seg_base_pending,    // Base for current relocation
    input  logic        eff_mask_pending,    // 32-bit effective-offset enable
    input  logic [31:0] lar_result,
    input  logic [31:0] llim_result,
    input  logic [31:0] lbas_result,
    input  logic [2:0]  fault_code,
    input  logic [31:0] fault_addr,
    input  logic [31:0] cr3,

    output logic [31:0] ind,
    output logic [31:0] ind_delta,
    output logic [31:0] ind_linear,          // Registered relocated IND
    output logic        ind_linear_valid,    // Relocation matches current IND
    output logic [31:0] ea,
    output logic [31:0] issue_ea,              // Combinational D2 effective address
    output logic [31:0] issue_linear,          // Combinational D2 relocated address
    output logic [1:0]  issue_linear_low       // Low address bits without full relocation
);

logic [1:0] ea_scale_r;
logic       ea_is_16bit_r;
logic       ea_scale_to_base_r;
logic [31:0] ea_partial_r;
logic [31:0] issue_ind_r;
logic [31:0] exec_ind_r;
logic        ind_owner_issue_r;
logic [31:0] issue_linear_r;
logic [31:0] exec_linear_r;
logic        linear_owner_issue_r;

wire [3:0] ind_op = ind_ctrl[3:0];
wire       ind_source_irf2 = ind_ctrl[4];
wire [2:0] ind_dest_class = ind_ctrl[7:5];
wire       ind_stssaf = ind_ctrl[8];

localparam [3:0] INDOP_PLUS_ALU  = 4'd1;
localparam [3:0] INDOP_ALU2      = 4'd2;
localparam [3:0] INDOP_SRC       = 4'd3;
localparam [3:0] INDOP_PLUS      = 4'd4;
localparam [3:0] INDOP_IN_PLUS_D = 4'd5;
localparam [3:0] INDOP_LAR       = 4'd6;
localparam [3:0] INDOP_LLIM      = 4'd7;
localparam [3:0] INDOP_LBAS      = 4'd8;
localparam [3:0] INDOP_LPCR      = 4'd9;

localparam [2:0] INDDEST_DESSTK = 3'd1;
localparam [2:0] INDDEST_DESCOD = 3'd2;
localparam [2:0] INDDEST_DESSEG = 3'd3;
localparam [2:0] INDDEST_PFERRC = 3'd4;
localparam [2:0] INDDEST_LATTTF = 3'd5;
localparam [2:0] INDDEST_PDBR   = 3'd6;

// Keep D2 and microcode address updates on independent register inputs. This
// prevents D2 admission from selecting through the much wider execution IND
// update mux while preserving issue priority on simultaneous boundaries.
assign ind = ind_owner_issue_r ? issue_ind_r : exec_ind_r;
assign ind_linear = linear_owner_issue_r ? issue_linear_r : exec_linear_r;

//=============================================================================
// D2 effective-address formation
//=============================================================================

function automatic logic [2:0] onehot_idx(input logic [7:0] onehot);
    onehot_idx = onehot[1] ? 3'd1 : onehot[2] ? 3'd2 :
                 onehot[3] ? 3'd3 : onehot[4] ? 3'd4 :
                 onehot[5] ? 3'd5 : onehot[6] ? 3'd6 :
                 onehot[7] ? 3'd7 : 3'd0;
endfunction

wire [63:0] ea_terms = ea_scale_operands(
    ea_base_value, ea_index_value, ea_scale_r, ea_scale_to_base_r);
wire [31:0] ea_term_a_live = ea_terms[63:32];
wire [31:0] ea_term_b_live = ea_terms[31:0];
// A simple EA has at most two live terms. Select them before the adder so the
// split does not leave a base+index+displacement cone in the normal D2 path.
wire        ea_simple_two_regs = ea_base.valid && ea_index.valid &&
                                 !ea_scale_to_base_r;
wire [31:0] ea_simple_a = ea_base.valid ? ea_term_a_live : ea_term_b_live;
wire [31:0] ea_simple_b = ea_simple_two_regs ? ea_term_b_live : displacement;
// PC98 mode stages every memory ModR/M EA. The constant selection removes
// load forwarding and GPR selection from the relocation/TLB input path.
wire [31:0] ea_add_a = (REGISTERED_EA || split_ea_use) ? ea_partial_r : ea_simple_a;
wire [31:0] ea_add_b = (REGISTERED_EA || split_ea_use) ? displacement : ea_simple_b;
wire [31:0] ea_offset_full = ea_add_a + ea_add_b;
wire [31:0] effective_addr = ea_is_16bit_r
                           ? {16'd0, ea_offset_full[15:0]} : ea_offset_full;
wire [31:0] linear32 = ea_offset_full + issue_seg_base;
wire [31:0] linear16 = {16'd0, ea_offset_full[15:0]} + issue_seg_base;
wire [31:0] effective_linear = (ea_is_16bit_r || !issue_eff_mask)
                             ? linear16 : linear32;
// Alignment participates in same-cycle VIPT admission. It depends only on the
// low address bits, so keep both full-width EA and relocation adders out of it.
wire [3:0] issue_linear_low_sum = {2'b0, ea_add_a[1:0]} +
                                  {2'b0, ea_add_b[1:0]} +
                                  {2'b0, issue_seg_base[1:0]};
assign issue_ea = effective_addr;
assign issue_linear = effective_linear;
assign issue_linear_low = issue_linear_low_sum[1:0];

always_ff @(posedge clk) begin
    if (!reset_n)
        ea_partial_r <= 32'd0;
    else if (split_ea_prepare)
        ea_partial_r <= ea_term_a_live + ea_term_b_live + split_ea_adjust;
end

always_ff @(posedge clk) begin
    if (d2_start) begin
        ea_base.valid <= |d2_ea.base_sel;
        ea_base.index <= onehot_idx(d2_ea.base_sel);
        ea_index.valid <= |d2_ea.index_sel;
        ea_index.index <= onehot_idx(d2_ea.index_sel);
        ea_scale_r <= d2_ea.scale;
        ea_is_16bit_r <= d2_ea.is16;
        ea_scale_to_base_r <= d2_ea.s2b;
    end
end

// synthesis translate_off
wire [31:0] reference_ea_full = ea_term_a_live + ea_term_b_live + displacement +
    (instr.ea_uses_post_pop_esp ? (instr.data32 ? 32'd4 : 32'd2) : 32'd0);
wire [31:0] reference_ea = ea_is_16bit_r ? {16'd0, reference_ea_full[15:0]} : reference_ea_full;
always @(posedge clk)
    if (reset_n && REGISTERED_EA && instr_issue && instr.has_modrm &&
        instr.modrm[7:6] != 2'b11 && !instr.has_moffs &&
        (!split_ea_use || effective_addr !== reference_ea))
        $fatal(1, "PC98 REGISTERED EA MISMATCH: staged=%08x live=%08x split=%b",
               effective_addr, reference_ea, split_ea_use);
// Prove the fused linear adder against the architectural relocate operation.
always @(posedge clk)
    if (reset_n && instr_issue && instr.has_modrm && !instr.stack_op &&
        !instr.has_moffs &&
        (effective_linear !==
         ((issue_eff_mask ? effective_addr :
                               {16'd0, effective_addr[15:0]}) +
          issue_seg_base)))
        $fatal(1,
               "POP-LIN FUSE MISMATCH: fused=%08x ref=%08x ea=%08x seg=%08x",
               effective_linear,
               (issue_eff_mask ? effective_addr :
                                    {16'd0, effective_addr[15:0]}) +
                   issue_seg_base,
               effective_addr, issue_seg_base);
// synthesis translate_on

//=============================================================================
// Relocation helpers and microcode IND updates
//=============================================================================

function automatic logic [31:0] relocate(input logic [31:0] offset);
    relocate = (eff_mask_pending ? offset : {16'd0, offset[15:0]}) +
               seg_base_pending;
endfunction

// Issue-time relocation bypasses the generic SEG_CMD next-state cone. The
// segmentation unit still receives INIT_SEG and commits identical state.
function automatic logic [31:0] relocate_issue(input logic [31:0] offset);
    relocate_issue = (issue_eff_mask ? offset : {16'd0, offset[15:0]}) +
                     issue_seg_base;
endfunction

// Preserve the dedicated microcode relocation cone used before extraction.
`Z486_KEEP wire [31:0] seg_base_pending_exec = seg_base_pending;

function automatic logic [31:0] relocate_exec(input logic [31:0] offset);
    relocate_exec = (eff_mask_pending ? offset : {16'd0, offset[15:0]}) +
                    seg_base_pending_exec;
endfunction

// Keep the IND update and segment relocation in the FPGA's fused adder.
function automatic logic [31:0] relocate_add2(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic        mask16
);
    relocate_add2 = mask16
                  ? ({16'd0, a[15:0] + b[15:0]} + seg_base_pending_exec)
                  : (a + b + seg_base_pending_exec);
endfunction

logic        exec_linear_write;
logic        exec_linear_three_term;
logic        exec_linear_mask16;
logic [31:0] exec_linear_source;
logic [31:0] exec_linear_a;
logic [31:0] exec_linear_b;
always_comb begin
    exec_linear_write = (seg_cmd == SEG_CMD_DESCSW) ||
                        (ind_stssaf && seg_sel == SEG_SS);
    exec_linear_three_term = 1'b0;
    exec_linear_mask16 = !eff_mask_pending;
    exec_linear_source = ind;
    exec_linear_a = ind;
    exec_linear_b = 32'd0;

    case (ind_op)
        INDOP_PLUS_ALU: begin
            exec_linear_a = ind_source_irf2 ? ind : source_value;
            exec_linear_b = instr_jcc ? alu_value_hold : alu_value;
            if (ind_dest_class == INDDEST_DESSTK)
                exec_linear_mask16 = !pe || !ss_stack32;
            else if (ind_dest_class == INDDEST_DESCOD)
                exec_linear_mask16 = !is_dword;
            else if (ind_dest_class == INDDEST_DESSEG)
                exec_linear_mask16 = !exec_addr32;
            exec_linear_write = 1'b1;
            exec_linear_three_term = 1'b1;
        end
        INDOP_ALU2: begin
            exec_linear_write = 1'b1;
            exec_linear_source = alu_value;
        end
        INDOP_SRC: begin
            exec_linear_write = 1'b1;
            exec_linear_source = source_value;
            if (ind_dest_class == INDDEST_DESSTK && (!pe || !ss_stack32))
                exec_linear_source = {16'd0, source_value[15:0]};
            else if (ind_dest_class == INDDEST_DESCOD && !is_dword)
                exec_linear_source = {16'd0, source_value[15:0]};
        end
        INDOP_PLUS: begin
            exec_linear_write = 1'b1;
            exec_linear_three_term = 1'b1;
            exec_linear_a = ind;
            exec_linear_b = alu_value;
        end
        INDOP_IN_PLUS_D: begin
            exec_linear_write = 1'b1;
            exec_linear_three_term = 1'b1;
            exec_linear_a = ind;
            exec_linear_b = ind_delta;
        end
        default: ;
    endcase
end

// Execution owns a separate relocation register. Updating this shadow in a
// simultaneous issue cycle is harmless because linear_owner_issue_r selects
// the newly issued address; removing issue priority here breaks the D2-to-EX
// control path without adding a pipeline stage.
always_ff @(posedge clk) begin
    if (!reset_n)
        exec_linear_r <= 32'd0;
    else if (exec && exec_linear_write) begin
        if (exec_linear_three_term)
            exec_linear_r <= relocate_add2(exec_linear_a, exec_linear_b,
                                            exec_linear_mask16);
        else
            exec_linear_r <= relocate_exec(exec_linear_source);
    end
end

always_ff @(posedge clk) begin
    if (instr_issue)
        ea <= branch_relative ? branch_target_eip : effective_addr;
end

// The execution IND value is a shadow while a simultaneous D2 issue owns the
// architectural output. Let it update independently so D2 admission and its
// segment-fault qualification do not select through the execution update mux.
// Ownership below still gives the newly issued instruction priority.
always_ff @(posedge clk) begin
    if (!reset_n) begin
        exec_ind_r <= 32'd0;
    end else if (exec) begin
        automatic logic mask16 = !eff_mask_pending;

        case (ind_op)
            INDOP_PLUS_ALU: begin
                automatic logic [31:0] next_ind;
                automatic logic [31:0] operand1;
                automatic logic [31:0] operand2;
                operand1 = ind_source_irf2 ? ind : source_value;
                operand2 = instr_jcc ? alu_value_hold : alu_value;
                if (ind_dest_class == INDDEST_DESSTK)
                    mask16 = !pe || !ss_stack32;
                else if (ind_dest_class == INDDEST_DESCOD)
                    mask16 = !is_dword;
                else if (ind_dest_class == INDDEST_DESSEG)
                    mask16 = !exec_addr32;
                next_ind = operand1 + operand2;
                if (mask16 && (ind_dest_class == INDDEST_DESSTK ||
                               ind_dest_class == INDDEST_DESCOD ||
                               ind_dest_class == INDDEST_DESSEG))
                    next_ind = {16'd0, next_ind[15:0]};
                exec_ind_r <= next_ind;
            end
            INDOP_ALU2: exec_ind_r <= alu_value;
            INDOP_SRC: begin
                automatic logic [31:0] next_ind = source_value;
                if (ind_dest_class == INDDEST_DESSTK && (!pe || !ss_stack32))
                    next_ind = {16'd0, next_ind[15:0]};
                else if (ind_dest_class == INDDEST_DESCOD && !is_dword)
                    next_ind = {16'd0, next_ind[15:0]};
                exec_ind_r <= next_ind;
            end
            INDOP_PLUS: begin
                automatic logic [31:0] next_ind = ind + alu_value;
                if (!pe && !exec_addr32)
                    next_ind = {16'd0, next_ind[15:0]};
                exec_ind_r <= next_ind;
            end
            INDOP_IN_PLUS_D: begin
                automatic logic [31:0] next_ind = ind + ind_delta;
                if (!pe ? !exec_addr32
                        : !(descsw_mode ? cs_stack32 : ss_stack32))
                    next_ind = {16'd0, next_ind[15:0]};
                exec_ind_r <= next_ind;
            end
            INDOP_LAR:  exec_ind_r <= lar_result;
            INDOP_LLIM: exec_ind_r <= llim_result;
            INDOP_LBAS: exec_ind_r <= lbas_result;
            INDOP_LPCR: begin
                case (ind_dest_class)
                    INDDEST_PFERRC: exec_ind_r <= {29'd0, fault_code};
                    INDDEST_LATTTF: exec_ind_r <= fault_addr;
                    INDDEST_PDBR:   exec_ind_r <= cr3;
                    default: ;
                endcase
            end
            default: ;
        endcase
    end
end

always_ff @(posedge clk) begin
    if (!reset_n) begin
        issue_ind_r <= 32'd0;
        ind_owner_issue_r <= 1'b0;
        ind_delta <= 32'd4;
        issue_linear_r <= 32'd0;
        linear_owner_issue_r <= 1'b0;
        ind_linear_valid <= 1'b0;
    end else if (instr_issue) begin
        linear_owner_issue_r <= 1'b1;
        ind_linear_valid <= 1'b0;
        ind_delta <= !instr.stack_op ? 32'd2 :
                     !instr.stack_dir ? (instr.data32 ? -32'd4 : -32'd2) :
                                        (instr.data32 ? 32'd4 : 32'd2);
        if (instr.stack_op && instr.stack_dir) begin
            automatic logic [31:0] stack_offset =
                ss_stack32 ? forwarded_esp : {16'd0, forwarded_esp[15:0]};
            issue_ind_r <= stack_offset;
            ind_owner_issue_r <= 1'b1;
            issue_linear_r <= relocate_issue(stack_offset);
            ind_linear_valid <= 1'b1;
        end else if (instr.stack_op && !instr.stack_dir) begin
            automatic logic [31:0] stack_offset = ss_stack32
                ? forwarded_esp - (instr.data32 ? 32'd4 : 32'd2)
                : {16'd0, forwarded_esp[15:0] -
                          (instr.data32 ? 16'd4 : 16'd2)};
            issue_ind_r <= stack_offset;
            ind_owner_issue_r <= 1'b1;
            issue_linear_r <= relocate_issue(stack_offset);
            ind_linear_valid <= 1'b1;
        end else if (instr.has_moffs) begin
            issue_ind_r <= instr.addr32 ? instr.immediate
                                        : {16'd0, instr.immediate[15:0]};
            ind_owner_issue_r <= 1'b1;
            issue_linear_r <= relocate_issue(instr.immediate);
            ind_linear_valid <= 1'b1;
        end else if (instr.has_modrm) begin
            issue_ind_r <= effective_addr;
            ind_owner_issue_r <= 1'b1;
            issue_linear_r <= effective_linear;
            ind_linear_valid <= 1'b1;
        end
    end else if (exec) begin
        case (ind_op)
            INDOP_PLUS_ALU: begin
                automatic logic [31:0] operand2;
                operand2 = instr_jcc ? alu_value_hold : alu_value;
                if (alu_source != ALUSRC_ZERO)
                    ind_delta <= operand2;
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b1;
            end
            INDOP_ALU2: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b1;
            end
            INDOP_SRC: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b1;
            end
            INDOP_PLUS: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b1;
                if (alu_source != ALUSRC_ZERO)
                    ind_delta <= alu_value;
            end
            INDOP_IN_PLUS_D: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b1;
            end
            INDOP_LAR: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b0;
            end
            INDOP_LLIM: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b0;
            end
            INDOP_LBAS: begin
                ind_owner_issue_r <= 1'b0;
                ind_linear_valid <= 1'b0;
            end
            INDOP_LPCR: begin
                case (ind_dest_class)
                    INDDEST_PFERRC: begin
                        ind_owner_issue_r <= 1'b0;
                    end
                    INDDEST_LATTTF: begin
                        ind_owner_issue_r <= 1'b0;
                    end
                    INDDEST_PDBR: begin
                        ind_owner_issue_r <= 1'b0;
                    end
                    default: ;
                endcase
                ind_linear_valid <= 1'b0;
            end
            default: ;
        endcase

        if (exec_linear_write)
            linear_owner_issue_r <= 1'b0;
    end
end

endmodule
