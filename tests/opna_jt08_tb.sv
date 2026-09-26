`timescale 1ns/1ps
module opna_jt08_tb;
    parameter integer KHZ=100000;
    reg clk=0,rstn=0,csn=1,wrn=1,rdn=1;
    reg [1:0] adr=0;
    reg [7:0] din=0;
    wire [7:0] dout;
    wire waitn,irqn;
    wire signed [15:0] l,r,ref_l,ref_r;
    wire [15:0] psg;
    wire [7:0] pa,pb;
    always #(500000.0/KHZ) clk=~clk;
    opna_jt08 #(.SYSFREQ(KHZ),.RHYTHM_HEX("rtl/vendor/jt08/rhythm.hex")) dut(
        .clk(clk),.rstn(rstn),.din(din),.adr(adr),.csn(csn),.rdn(rdn),.wrn(wrn),
        .dout(dout),.doe(),.waitn(waitn),.irqn(irqn),.snd_l(l),.snd_r(r),.snd_psg(psg),
        .pain(8'h5a),.pbin(8'ha5),.paout(pa),.pbout(pb),.paoe(),.pboe());
    // Same IO timing, with modulation disabled in the control instance.
    wire [7:0] selected=dut.synth.u_jt12.u_mmr.selected_register;
    wire [7:0] ref_din=adr[0] && ((adr==1 && selected==8'h22) || selected[7:4]==9) ? 8'd0 : din;
    opna_jt08 #(.SYSFREQ(KHZ),.RHYTHM_HEX("rtl/vendor/jt08/rhythm.hex")) reference_fm(
        .clk(clk),.rstn(rstn),.din(ref_din),.adr(adr),.csn(csn),.rdn(rdn),.wrn(wrn),
        .dout(),.doe(),.waitn(),.irqn(),.snd_l(ref_l),.snd_r(ref_r),.snd_psg(),
        .pain(8'h5a),.pbin(8'ha5),.paout(),.pbout(),.paoe(),.pboe());
    integer writes=0;
    always @(posedge clk) if(rstn && dut.state==2) writes=writes+1;
    task cycles(input integer n); repeat(n) @(negedge clk); endtask
    task reset;
        begin rstn=0; cycles(30); rstn=1; cycles(KHZ/5); end
    endtask
    task transfer(input bit writing,input [1:0] portno,input [7:0] value,output [7:0] result);
        integer timeout_count,before_writes;
        begin
            @(negedge clk); adr=portno; din=value; csn=0; wrn=!writing; rdn=writing;
            before_writes=writes; cycles(1); timeout_count=0;
            while(!waitn && timeout_count<KHZ) begin cycles(1); timeout_count=timeout_count+1; end
            if(!waitn) $fatal(1,"sound IO never acknowledged");
            result=dout;
            cycles(7); // hold after acknowledgement: must not duplicate writes
            if(writes-before_writes!=(writing ? 1 : 0)) $fatal(1,"held sound IO duplicated/lost");
            csn=1; wrn=1; rdn=1; cycles(3);
        end
    endtask
    reg [7:0] unused;
    task bus(input [1:0] a,input [7:0] d); transfer(1,a,d,unused); endtask
    task regwrite(input integer bank,input [7:0] regno,input [7:0] value);
        begin bus(bank*2,regno); bus(bank*2+1,value); end
    endtask
    task tone(input integer channel,input [7:0] pan,input [7:0] lfo,input [7:0] envelope);
        integer bank,c,op;
        begin
            bank=channel/3; c=channel%3;
            regwrite(0,8'h29,8'h80); regwrite(0,8'h22,lfo);
            for(op=0;op<4;op=op+1) begin
                regwrite(bank,8'h30+c+op*4,8'h01);
                regwrite(bank,8'h40+c+op*4,op==3 ? 8'h18 : 8'h7f);
                regwrite(bank,8'h50+c+op*4,8'h1f);
                regwrite(bank,8'h60+c+op*4,8'h80);
                regwrite(bank,8'h70+c+op*4,envelope!=0 ? 8'h1f : 8'h00);
                regwrite(bank,8'h80+c+op*4,8'h0f);
                regwrite(bank,8'h90+c+op*4,envelope);
            end
            regwrite(bank,8'hb0+c,8'h07); regwrite(bank,8'hb4+c,pan | 8'h37);
            regwrite(bank,8'ha4+c,8'h22); regwrite(bank,8'ha0+c,8'h69);
            regwrite(0,8'h28,8'hf0 | (bank*4+c));
        end
    endtask
    longint energy_l,energy_r;
    integer samples,differences,psg_min,psg_max;
    task measure(input integer milliseconds);
        integer k;
        begin
            energy_l=0; energy_r=0; samples=0; differences=0; psg_min=65535;psg_max=0;
            for(k=0;k<KHZ*milliseconds;k=k+1) begin
                @(negedge clk);
                if(dut.synth.u_jt12.clk_en && dut.synth.u_jt12.zero) begin
                    energy_l=energy_l+(l<0 ? -integer'(l) : integer'(l));
                    energy_r=energy_r+(r<0 ? -integer'(r) : integer'(r));
                    samples=samples+1;
                    if(l!==ref_l || r!==ref_r) differences=differences+1;
                    if(psg<psg_min) psg_min=psg;
                    if(psg>psg_max) psg_max=psg;
                end
            end
        end
    endtask
    time psg_start;
    integer c,p,i,n;
    task psg_sample_bus_test;
        reg [7:0] value;
        integer sample_index;
        begin
            reset;
            // Back-to-back address/data writes must preserve adjacent PSG
            // registers even when no FM clock-enable occurs between them.
            for(sample_index=0;sample_index<6;sample_index=sample_index+1)
                regwrite(0,sample_index*2,8'h11+sample_index);
            for(sample_index=0;sample_index<6;sample_index=sample_index+1) begin
                bus(0,sample_index*2); transfer(0,1,0,value);
                if(value!=(8'h11+sample_index))
                    $fatal(1,"Fast PSG address change corrupted register %0d: %h",sample_index*2,value);
            end
            // Rusty's PDR sample ISR polls busy then writes volume register A.
            // A stream of PSG volume writes must not start an FM busy period.
            psg_start=$time;
            for(sample_index=0;sample_index<32;sample_index=sample_index+1) begin
                transfer(0,0,0,value);
                if(value[7]) $fatal(1,"PSG sample write incorrectly asserts busy");
                regwrite(0,8'h0a,sample_index&15);
                transfer(0,1,0,value);
                if(value!=(sample_index&15)) $fatal(1,"PSG sample volume write lost");
            end
            if($time-psg_start>50000) $fatal(1,"PSG stream stalled: %0t",$time-psg_start);
            // The optimization must not remove the FM update interlock.
            regwrite(0,8'h30,8'h01); transfer(0,0,0,value);
            if(!value[7]) $fatal(1,"FM write busy protection removed");
            regwrite(0,8'h34,8'h02); cycles(KHZ/20);
            transfer(0,0,0,value);
            if(value[7]) $fatal(1,"FM busy did not clear");
            $display("PASS %0d kHz fast PSG sample writes/readback, no PSG busy, FM busy retained",KHZ);
        end
    endtask
    reg [7:0] status;
    initial begin
`ifndef NEGATIVE_LFO
        psg_sample_bus_test;
`ifdef PSG_ONLY
        $finish;
`endif
        reset;
        // Mirrors the identification operation used by Rusty's ONGCHK.COM.
        bus(0,8'hff); transfer(0,1,0,status);
        if(status!=1) $fatal(1,"OPNA ID is not 01: %h",status);
        transfer(0,2,0,status);
        if(status==8'hff) $fatal(1,"OPNA extended status absent");
        regwrite(0,0,8'h23); regwrite(0,1,8'h01);
        bus(0,0); transfer(0,1,0,status);
        if(status!=8'h23) $fatal(1,"PSG register readback wrong");
        regwrite(0,7,8'hff); bus(0,14); transfer(0,1,0,status);
        if(status!=8'h5a) $fatal(1,"Joystick input readback wrong");
        regwrite(0,15,8'h40);
        if(pb!=8'h40) $fatal(1,"Joystick select output missing");
        // Timer B must both assert and clear on a fast one-transaction write.
        regwrite(0,8'h29,8'h83); regwrite(0,8'h26,8'hff); regwrite(0,8'h27,8'h0a);
        n=0; while(irqn && n<KHZ) begin cycles(1); n=n+1; end
        if(irqn) $fatal(1,"OPNA timer IRQ missing");
        transfer(0,0,0,status); if(!status[1]) $fatal(1,"Timer B status missing");
        regwrite(0,8'h27,8'h30); cycles(100);
        transfer(0,0,0,status);
        if(!irqn || status[1:0]!=0) $fatal(1,"Timer clear lost");
        $display("PASS %0d kHz OPNA chip ID, extended status, PSG/GPIO, timer IRQ/clear, held IO",KHZ);
        for(c=0;c<6;c=c+1) for(p=0;p<2;p=p+1) begin
            reset; tone(c,p==0 ? 8'h80 : 8'h40,0,0); cycles(KHZ); measure(4);
            if(samples<220 || samples>224) $fatal(1,"FM sample rate wrong: %0d",samples);
            if(p==0 && (energy_l<10000 || energy_r!=0)) $fatal(1,"FM%0d left missing/leaking: %0d/%0d",c+1,energy_l,energy_r);
            if(p==1 && (energy_r<10000 || energy_l!=0)) $fatal(1,"FM%0d right missing/leaking: %0d/%0d",c+1,energy_l,energy_r);
            $display("PASS %0d kHz FM%0d pan%0d energy %0d/%0d",KHZ,c+1,p,energy_l,energy_r);
        end
        for(c=0;c<3;c=c+1) begin
            reset; regwrite(0,7,8'h3f^(1<<c)); regwrite(0,c*2,8'h60);
            regwrite(0,c*2+1,0); regwrite(0,8+c,15); measure(4);
            if(psg_max-psg_min<100) $fatal(1,"PSG%0d missing",c+1);
            $display("PASS %0d kHz PSG%0d range %0d..%0d",KHZ,c+1,psg_min,psg_max);
        end
        for(c=0;c<6;c=c+1) begin
            reset; regwrite(0,8'h11,8'h3f); regwrite(0,8'h18+c,8'hdf);
            regwrite(0,8'h10,1<<c); measure(12);
            if(energy_l<1000 || energy_r<1000) $fatal(1,"Rhythm%0d missing: %0d/%0d",c+1,energy_l,energy_r);
            $display("PASS %0d kHz rhythm%0d energy %0d/%0d",KHZ,c+1,energy_l,energy_r);
        end
        reset; tone(0,8'hc0,0,0); measure(12);
        if(differences!=0) $fatal(1,"Unmodulated reference differs");
`endif
        reset; tone(0,8'hc0,8'h0f,0); measure(12);
        if(differences<100) $fatal(1,"LFO has no waveform effect");
        reset; tone(0,8'hc0,0,8'h0e); measure(12);
        if(differences<100) $fatal(1,"SSG envelope has no waveform effect");
        $display("PASS %0d kHz LFO and SSG-EG affect output waveforms",KHZ);
        $finish;
    end
    initial begin #500000000; $fatal(1,"OPNA test timeout"); end
endmodule
