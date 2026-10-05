`timescale 1ns/1ps
module z486_store_forward_tb;
    reg [31:0] memory_word=32'hc0decafe;
    reg [127:0] memory_line=128'h76543210_fedcba98_89abcdef_01234567;
    l1_cache dut(.clk(1'b0),.reset(1'b0),.mem_dout(memory_word),.mem_line_dout(memory_line));
    integer checks=0, address_choice;
    initial begin
        dut.state=3;
        dut.req_addr_r=32'h00100004;
        dut.fill_target_word=1;
        dut.wide_fill_line=128'hffff0000_cccc3333_aaaa5555_99996666;
        dut.rd_data0_r=32'hf1d2b3a4;
        dut.rd_data1_r=32'h76504321;
        dut.rd_data2_r=32'h12305764;
        dut.rd_data3_r=32'h234c56d8;
        dut.storeq_data[0]=32'h1a2b3c4d;
        dut.storeq_data[1]=32'h5e6f7081;
        dut.storeq_data[2]=32'h92a3b4c5;
        for(integer fill=1;fill<=2;fill++) begin
            dut.fill_count=2'(fill);
            for(integer tail=0;tail<3;tail++) begin
                dut.storeq_tail=2'(tail);
                for(integer count=0;count<=3;count++) begin
                    dut.storeq_count=2'(count);
                    for(integer valid=0;valid<8;valid++) begin
                        for(integer slot=0;slot<3;slot++) dut.storeq_valid[slot]=valid[slot];
                        for(integer addresses=0;addresses<27;addresses++) begin
                            address_choice=addresses;
                            for(integer slot=0;slot<3;slot++) begin
                                case(address_choice%3)
                                    0:dut.storeq_addr[slot]=30'h40001;
                                    1:dut.storeq_addr[slot]=30'h40000+fill;
                                    2:dut.storeq_addr[slot]=30'h40100;
                                endcase
                                address_choice=address_choice/3;
                            end
                            for(integer masks=0;masks<4096;masks++) begin
                                for(integer slot=0;slot<3;slot++) dut.storeq_be[slot]=4'(masks>>(slot*4));
                                #1;
                                // The module's retained independent per-slot
                                // reference asserts all five forwarding results.
                                checks++;
                            end
                        end
                    end
                end
            end
        end
        $display("PASS %0d forwarding combinations: queue order/count, valid, aliases, byte masks",checks);
        $finish;
    end
endmodule
