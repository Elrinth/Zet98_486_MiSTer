`timescale 1ns/1ps
// Two floppy images mounted in the same cycle, then both drives read
// concurrently. One host model serves one slot at a time over the shared
// sd_buff bus, as the MiSTer HPS does. The shared converter must keep each
// drive's geometry and cache apart.
module native_image_dual_tb;
reg clk=0; always #5 clk=~clk;
reg [1:0] mounted=0;
reg [63:0] image_size;
wire [1:0] media_mounted,media_readonly,invalid;
wire [63:0] media_size[2];
reg [31:0] disk_lba[2];
reg [1:0] disk_rd=0,disk_wr=0;
wire [7:0] disk_buff_din[2];
wire [1:0] disk_ack,disk_buff_wr;
wire [8:0] disk_buff_addr[2];
wire [7:0] disk_buff_dout[2];
wire [31:0] host_lba[2];
wire [1:0] host_rd,host_wr;
wire [7:0] host_buff_din[2];
reg [1:0] host_ack=0;
reg host_buff_wr=0;
reg [8:0] host_buff_addr=0;
reg [7:0] host_buff_dout=0;
assign disk_buff_din[0]=0; assign disk_buff_din[1]=0;
pc98_floppy_images dut(.clk(clk),.mounted(mounted),.readonly(1'b0),.image_size(image_size),
 .media_mounted(media_mounted),.media_readonly(media_readonly),.media_size(media_size),
 .disk_lba(disk_lba),.disk_rd(disk_rd),.disk_wr(disk_wr),.disk_buff_din(disk_buff_din),
 .disk_ack(disk_ack),.disk_buff_wr(disk_buff_wr),.disk_buff_addr(disk_buff_addr),.disk_buff_dout(disk_buff_dout),
 .host_lba(host_lba),.host_rd(host_rd),.host_wr(host_wr),.host_buff_din(host_buff_din),
 .host_ack(host_ack),.host_buff_wr(host_buff_wr),.host_buff_addr(host_buff_addr),.host_buff_dout(host_buff_dout),
 .invalid(invalid));
reg [7:0] source0[0:2097151], source1[0:2097151], expected0[0:2097151], expected1[0:2097151];
integer size0,size1,exp0,exp1,fd,phase=0,count=0,slot=0,last=1,notes0=0,notes1=0,got0=0,got1=0;
reg [31:0] held;
string p;
// Shared host: round-robin between pending slots, one transfer at a time.
always @(negedge clk) begin
 host_buff_wr=0;
 case(phase)
 0: if(host_rd!=0) begin
    if(host_wr!=0) $fatal(1,"host write during read-only test");
    slot=(host_rd==2'b11) ? 1-last : (host_rd[1] ? 1 : 0); last=slot;
    held=host_lba[slot];count=0;phase=1;
 end
 1: begin host_ack[slot]=1;phase=2;end
 2: begin
    host_buff_wr=1;host_buff_addr=count;
    if(slot==0) host_buff_dout=held*512+count<size0 ? source0[held*512+count] : 0;
    else host_buff_dout=held*512+count<size1 ? source1[held*512+count] : 0;
    count=count+1;if(count==512) phase=3;
 end
 3: begin host_ack[slot]=0;phase=0;end
 endcase
end
always @(posedge clk) begin
 if(media_mounted[0]) notes0=notes0+1;
 if(media_mounted[1]) notes1=notes1+1;
 if(disk_ack[0] && disk_buff_wr[0]) begin
  if(disk_buff_addr[0]!==got0[8:0] || disk_buff_dout[0]!==(disk_lba[0]*512+got0<exp0 ? expected0[disk_lba[0]*512+got0] : 8'b0))
   $fatal(1,"drive 0 LBA=%0d offset=%0d actual=%h",disk_lba[0],got0,disk_buff_dout[0]);
  got0=got0+1;
 end
 if(disk_ack[1] && disk_buff_wr[1]) begin
  if(disk_buff_addr[1]!==got1[8:0] || disk_buff_dout[1]!==(disk_lba[1]*512+got1<exp1 ? expected1[disk_lba[1]*512+got1] : 8'b0))
   $fatal(1,"drive 1 LBA=%0d offset=%0d actual=%h",disk_lba[1],got1,disk_buff_dout[1]);
  got1=got1+1;
 end
end
task read0(input integer lba);
 @(negedge clk);disk_lba[0]=lba;disk_rd[0]=1;got0=0;
 wait(disk_ack[0]);@(negedge clk);disk_rd[0]=0;wait(!disk_ack[0]);@(negedge clk);
 if(got0!=512) $fatal(1,"drive 0 short transfer %0d at %0d",got0,lba);
endtask
task read1(input integer lba);
 @(negedge clk);disk_lba[1]=lba;disk_rd[1]=1;got1=0;
 wait(disk_ack[1]);@(negedge clk);disk_rd[1]=0;wait(!disk_ack[1]);@(negedge clk);
 if(got1!=512) $fatal(1,"drive 1 short transfer %0d at %0d",got1,lba);
endtask
initial begin
 disk_lba[0]=0;disk_lba[1]=0;
 if(!$value$plusargs("image0=%s",p)) $fatal; fd=$fopen(p,"rb");size0=$fread(source0,fd);$fclose(fd);
 if(!$value$plusargs("expected0=%s",p)) $fatal; fd=$fopen(p,"rb");exp0=$fread(expected0,fd);$fclose(fd);
 if(!$value$plusargs("image1=%s",p)) $fatal; fd=$fopen(p,"rb");size1=$fread(source1,fd);$fclose(fd);
 if(!$value$plusargs("expected1=%s",p)) $fatal; fd=$fopen(p,"rb");exp1=$fread(expected1,fd);$fclose(fd);
 // MiSTer reports one size per pulse; mount drive 1 while drive 0 parses.
 repeat(5) @(negedge clk);image_size=size0;mounted=1;@(negedge clk);mounted=0;
 image_size=size1;mounted=2;@(negedge clk);mounted=0;
 wait(notes0>=2 && notes1>=2);repeat(3) @(negedge clk);
 if(invalid!=0 || media_size[0]!=exp0 || media_size[1]!=exp1)
  $fatal(1,"sizes %0d/%0d expected %0d/%0d invalid=%b",media_size[0],media_size[1],exp0,exp1,invalid);
 fork
  begin read0(0);read0(2);for(integer l=5;l<(exp0+511)/512;l=l+37) read0(l);read0((exp0-1)/512);read0(3);end
  begin read1(1);read1(0);for(integer l=9;l<(exp1+511)/512;l=l+41) read1(l);read1((exp1-1)/512);read1(4);end
 join
 // Remount drive 0 while drive 1 keeps reading.
 fork
  begin @(negedge clk);image_size=size0;mounted=1;@(negedge clk);mounted=0;end
  begin read1(7);read1(2);end
 join
 wait(notes0>=4);repeat(3) @(negedge clk);
 read0(6);read1(8);
 $display("PASS: dual drives %0d/%0d bytes",exp0,exp1);$finish;
end
initial begin #200000000;$fatal(1,"dual image timeout");end
endmodule
