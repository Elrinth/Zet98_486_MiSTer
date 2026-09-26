`timescale 1ns/1ps
module boot_prompt_tb;
    reg clk=0, reset=1;
    always #5 clk=!clk;
    reg [2:0] prompt=0;
    wire ce,hs,vs,de;
    wire [7:0] r,g,b;
    video_output #(.BOOT_TEXT_FILE("rtl/assets/boot-text.mem"),
                   .BOOT_FONT_FILE("rtl/assets/boot-font.mem")) dut(
        .clk(clk),.reset(reset),.test_pattern(1'b0),.boot_prompt(prompt),
        .native_ce(1'b1),.native_r(8'h12),.native_g(8'h34),.native_b(8'h56),
        .native_hs(1'b0),.native_vs(1'b0),.native_de(1'b1),
        .ce(ce),.r(r),.g(g),.b(b),.hs(hs),.vs(vs),.de(de)
    );
    integer page,fd,count,frames;
    reg prev_vs;
    string folder;
    task tick;
        begin @(posedge clk); #1; end
    endtask
    initial begin
        if(!$value$plusargs("output=%s",folder)) $fatal(1,"Missing output directory");
        tick; reset=0;
        for(page=1;page<=4;page=page+1) begin
            prompt=page; prev_vs=0; frames=0;
            // Two public VS edges guarantee that the page switch has latched.
            while(frames<2) begin
                tick;
                if(ce) begin
                    if(vs && !prev_vs) frames=frames+1;
                    prev_vs=vs;
                end
            end
            fd=$fopen($sformatf("%s/page%0d.ppm",folder,page),"wb");
            if(!fd) $fatal(1,"Cannot create frame");
            $fwrite(fd,"P6\n640 480\n255\n"); count=0;
            while(count<640*480) begin
                tick;
                if(ce && de) begin
                    $fwrite(fd,"%c%c%c",r,g,b); count=count+1;
                end
            end
            $fclose(fd);
        end
        prompt=0;
        repeat(1300000) tick;
        if(!ce || !de || {r,g,b}!==24'h123456)
            $fatal(1,"Boot screen did not release native video");
        $display("PASS: all four prompt frames and native-video handoff captured");
        $finish;
    end
    initial begin #200000000; $fatal(1,"Prompt timeout"); end
endmodule
