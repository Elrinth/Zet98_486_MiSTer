`timescale 1ns/1ps
// Match the issued instruction and architectural vector, independent of IDT base.
module crash_recorder_gp_tb;
    reg clk=0; always #5 clk=~clk;
    reg pe=0, vm=0, gate_read=0, issue=0;
    reg [7:0] vector=0;
    reg [31:0] issued_ip=0, gate_addr=32'h00123468;
    reg [127:0] fault_payload=128'h0123456789abcdef0011223344556677;
    reg [127:0] operand=128'hfedcba98765432107766554433221100;
    wire tx;
    z486_crash_recorder #(.CLOCK_HZ(1152000),.DE_TRIGGER(1),.GP_FREEZE_IP(17'h1d5f2)) dut(
        .clk(clk),.pe(pe),.vm(vm),.gate_read(gate_read),.gate_addr(gate_addr),.gate_vector(vector),
        .fault_context(fault_payload),.fault_operand(operand),.cs(16'h123f),.eip(32'hd5f2),.eflags(32'h302),
        .pf_code(3'd0),.pf_addr(32'd0),.triple_fault(1'b0),.port_f0_write(1'b0),.port_f0_data(8'd0),
        .page_fault(1'b0),.walk_pde(32'd0),.walk_pte(32'd0),.cr3(32'd0),.a20(1'b1),.sp(16'hff00),
        .mem_write(1'b0),.mem_addr(32'd0),.mem_data(32'd0),.mem_be(4'd0),
        .io_wr(1'b0),.io_rd(1'b0),.io_addr(16'd0),.io_wdata(32'd0),.io_rdata(32'd0),
        .insn_issue(issue),.insn_eip(issued_ip),.tx(tx));
    task automatic insn(input [31:0] ip);
        @(negedge clk); issued_ip=ip; issue=1;
        @(negedge clk); issue=0;
    endtask
    task automatic gate(input [7:0] v);
        @(negedge clk); vector=v; gate_read=1;
        @(negedge clk); gate_read=0;
    endtask
    task automatic rx_byte(output [7:0] b);
        @(negedge tx); repeat(15) @(posedge clk);
        for(integer i=0;i<8;i++) begin b[i]=tx; repeat(10) @(posedge clk); end
    endtask
    reg [7:0] line[0:63]; integer n=0, count=0; reg done=0, seen_c=0, seen_d=0, seen_b=0;
    reg [127:0] last_e;
    function automatic [3:0] hv(input [7:0] c); hv=c<="9"?c-"0":c-"A"+10; endfunction
    initial forever begin : receiver
        reg [7:0] b; reg [127:0] value;
        rx_byte(b);
        if(b==10) begin
            value=0;
            if(n==33) for(integer i=1;i<33;i++) value={value[123:0],hv(line[i])};
            case(line[0])
              "C": begin if(value!==128'h0123456789abcdef0011223344556677) $fatal(1,"context changed"); seen_c=1; end
              "D": begin if(!seen_c || value!==128'hfedcba98765432107766554433221100) $fatal(1,"operand changed/order"); seen_d=1; end
              "B": begin if(!seen_d) $fatal(1,"missing fault snapshots"); seen_b=1; end
              "E": if(seen_b) begin count++; last_e=value; end
              "Z": if(seen_b) done=1;
            endcase
            n=0;
        end else begin line[n]=b; n++; end
    end
    initial begin
        repeat(20) @(posedge clk);
        pe=1; repeat(4) @(posedge clk);
        insn(32'h1111); gate(13);
        if(dut.frozen) $fatal(1,"froze at unrelated IP");
        insn(32'hd5f2); gate(14);
        if(dut.frozen) $fatal(1,"froze on page fault");
        vm=1; gate(13); vm=0;
        if(dut.frozen) $fatal(1,"froze in VM86");
        gate(13);
        if(!dut.frozen) $fatal(1,"did not freeze on target GP");
        fault_payload=0; operand=0; gate(14);
        wait(done);
        if(count!=256 || last_e[127:124]!==4'd1 || last_e[107:76]!==32'hd5f2 || last_e[75:44]!==32'h00123468)
            $fatal(1,"wrong frozen ring endpoint %h count=%0d",last_e,count);
        $display("PASS: protected GP IP/vector match, VM86 rejection, frozen descriptor/operand snapshots and UART framing");
        $finish;
    end
    initial begin #400000000; $fatal(1,"timeout"); end
endmodule
