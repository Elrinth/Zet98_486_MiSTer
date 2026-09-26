`timescale 1ns/1ps
module native_image_tb;
parameter FLOPPY=1;
parameter SLOT=0; // floppy: which drive of the shared converter is exercised
reg clk=0; always #5 clk=~clk;
reg mounted=0, readonly=0;
reg [63:0] image_size;
wire media_mounted,media_readonly,invalid;
wire [63:0] media_size;
reg [31:0] disk_lba=0;
reg disk_rd=0,disk_wr=0;
reg [7:0] disk_buff_din=0;
wire disk_ack,disk_buff_wr;
wire [8:0] disk_buff_addr;
wire [7:0] disk_buff_dout;
wire [31:0] host_lba;
wire host_rd,host_wr;
wire [7:0] host_buff_din;
reg host_ack=0,host_buff_wr=0;
reg [8:0] host_buff_addr=0;
reg [7:0] host_buff_dout=0;
generate if(FLOPPY) begin
// The other drive stays idle; the shared converter must serve SLOT alone.
wire [1:0] m2,ro2,ack2,bw2,hrd,hwr,inv2;
wire [63:0] size2[2];
wire [31:0] lba2[2],hlba2[2];
wire [7:0] din2[2],hdin2[2],dout2[2];
wire [8:0] addr2[2];
assign lba2[SLOT]=disk_lba; assign lba2[1-SLOT]=0;
assign din2[SLOT]=disk_buff_din; assign din2[1-SLOT]=0;
pc98_floppy_images dut(.clk(clk),.mounted(SLOT ? {mounted,1'b0} : {1'b0,mounted}),.readonly(readonly),
 .image_size(image_size),.media_mounted(m2),.media_readonly(ro2),.media_size(size2),
 .disk_lba(lba2),.disk_rd(SLOT ? {disk_rd,1'b0} : {1'b0,disk_rd}),.disk_wr(SLOT ? {disk_wr,1'b0} : {1'b0,disk_wr}),
 .disk_buff_din(din2),.disk_ack(ack2),.disk_buff_wr(bw2),.disk_buff_addr(addr2),.disk_buff_dout(dout2),
 .host_lba(hlba2),.host_rd(hrd),.host_wr(hwr),.host_buff_din(hdin2),
 .host_ack(SLOT ? {host_ack,1'b0} : {1'b0,host_ack}),.host_buff_wr(host_buff_wr),
 .host_buff_addr(host_buff_addr),.host_buff_dout(host_buff_dout),.invalid(inv2));
assign media_mounted=m2[SLOT]; assign media_readonly=ro2[SLOT]; assign media_size=size2[SLOT];
assign disk_ack=ack2[SLOT]; assign disk_buff_wr=bw2[SLOT]; assign disk_buff_addr=addr2[SLOT];
assign disk_buff_dout=dout2[SLOT]; assign host_lba=hlba2[SLOT]; assign host_rd=hrd[SLOT];
assign host_wr=hwr[SLOT]; assign host_buff_din=hdin2[SLOT]; assign invalid=inv2[SLOT];
always @(posedge clk) if(hrd[1-SLOT] || hwr[1-SLOT] || ack2[1-SLOT] || m2[1-SLOT])
 $fatal(1,"idle drive %0d was touched",1-SLOT);
end else begin
pc98_hdi_image dut(.*);
assign disk_buff_addr=host_buff_addr;
assign disk_buff_dout=host_buff_dout;
assign host_buff_din=disk_buff_din;
end endgenerate
reg [7:0] source[0:2097151], expected[0:2097151];
integer host_phase=0,host_count=0,received=0,size_expected,fd;
integer reject=0,direct=0,notifications=0,requests=0;
reg [31:0] held_lba;
reg reading=0,writing_host=0;
integer header_bytes,original_header[0:4095];
always @* disk_buff_din=host_buff_addr[7:0]^8'h69;
always @(negedge clk) begin
 host_buff_wr=0;
 case(host_phase)
 0: if(host_rd || host_wr) begin
    if(host_wr && FLOPPY && !direct) $fatal(1,"native source modified");
    held_lba=host_lba;writing_host=host_wr;host_count=0;host_phase=1;requests=requests+1;
 end
 1: begin host_ack=1;host_phase=2;end
 2: begin
    host_buff_wr=!writing_host;host_buff_addr=host_count;
    if(writing_host) source[held_lba*512+host_count]=host_count[7:0]^8'h69;
    host_buff_dout=held_lba*512+host_count<image_size ? source[held_lba*512+host_count] : 0;
    host_count=host_count+1;if(host_count==512) host_phase=3;
 end
 3: begin host_ack=0;host_phase=0;end
 endcase
end
always @(posedge clk) begin
 if(media_mounted) notifications=notifications+1;
 if(reading && disk_ack && disk_buff_wr) begin
   if(disk_buff_addr !== received[8:0]) $fatal(1,"address %d wanted %d",disk_buff_addr,received);
   if(disk_buff_dout !== (disk_lba*512+received<size_expected ? expected[disk_lba*512+received] : 8'b0))
     $fatal(1,"byte LBA=%d offset=%d actual=%h expected=%h",disk_lba,received,disk_buff_dout,expected[disk_lba*512+received]);
   received=received+1;
 end
end
task write_sector(input integer lba);
 @(negedge clk);disk_lba=lba;disk_wr=1;
 wait(disk_ack);@(negedge clk);disk_wr=0;
 wait(!disk_ack);@(negedge clk);
 for(integer i=0;i<512;i=i+1) expected[lba*512+i]=i[7:0]^8'h69;
 sector(lba);
endtask
task sector(input integer lba);
 @(negedge clk);disk_lba=lba;disk_rd=1;received=0;reading=1;
 wait(disk_ack);@(negedge clk);disk_rd=0;
 wait(!disk_ack);@(negedge clk);reading=0;
 if(received!=512) $fatal(1,"short transfer %d bytes at %d",received,lba);
endtask
string path,oracle;
initial begin
 if(!$value$plusargs("image=%s",path) || !$value$plusargs("expected=%s",oracle)) $fatal;
 fd=$fopen(path,"rb");image_size=$fread(source,fd);$fclose(fd);
 fd=$fopen(oracle,"rb");size_expected=$fread(expected,fd);$fclose(fd);
 if($value$plusargs("reject=%d",reject)) begin end
 if($value$plusargs("direct=%d",direct)) begin end
 repeat(5) @(negedge clk);mounted=1;@(negedge clk);mounted=0;
 wait(notifications>=2);repeat(3) @(negedge clk);
 if(reject) begin
   if(!invalid || media_size!=0) $fatal(1,"invalid format accepted");
 end else begin
   if(invalid || media_size!=size_expected) $fatal(1,"media size=%d expected=%d invalid=%d",media_size,size_expected,invalid);
   if(FLOPPY && !direct && !media_readonly) $fatal(1,"native floppy lacks write protection");
   sector(0);sector(1);sector(2);
   for(integer l=7;l<(size_expected+511)/512;l=l+29) sector(l);
   sector((size_expected-1)/512);sector(0);sector(17);sector(3);
   if(!FLOPPY) begin
     header_bytes=image_size-size_expected;
     for(integer i=0;i<header_bytes;i=i+1) original_header[i]=source[i];
     write_sector(0);write_sector(size_expected/512-1);
     for(integer i=0;i<header_bytes;i=i+1) if(source[i]!=original_header[i]) $fatal(1,"HDI header modified");
   end
 end
 @(negedge clk);image_size=0;mounted=1;@(negedge clk);mounted=0;
 repeat(4) @(negedge clk);if(media_size!=0) $fatal(1,"eject failed");
 $display("PASS: %s reject=%0d %0d host reads",path,reject,requests);$finish;
end
initial begin #50000000;$fatal(1,"image transport timeout");end
endmodule
