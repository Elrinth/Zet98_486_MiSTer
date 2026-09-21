// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// PC-98 ATA PIO task file, backed by one MiSTer raw-image slot. All signals
// share clk. This is a controller, not a disk BIOS or an ATAPI implementation.
// Port layout follows NP2kai cbus/ideio.c (5939e0c); no emulator code is used.
// Only channel 0/master exists. Geometry is 16 heads, 32 sectors (512 bytes).
// Data is 16-bit at 0640h; task-file registers occupy even low-byte ports.
module pc98_ide (
    input wire clk, reset,
    input wire [15:0] io_address, io_writedata,
    input wire [1:0] io_select,
    input wire io_read, io_write,
    output reg [15:0] io_readdata,
    output wire io_oe, irq,
    input wire image_mounted, image_readonly,
    input wire [63:0] image_size,
    output reg [31:0] sd_lba = 0,
    output wire sd_rd, sd_wr,
    input wire sd_ack,
    input wire [8:0] sd_buff_addr,
    input wire [7:0] sd_buff_dout,
    output wire [7:0] sd_buff_din,
    input wire sd_buff_wr
);
    localparam IDLE=0, READ_START=1, READ_WAIT=2, READ_DATA=3,
        WRITE_DATA=4, WRITE_START=5, WRITE_WAIT=6, IDENTIFY=7;
    reg [2:0] state;
    reg present = 0, readonly = 1;
    reg [27:0] capacity = 0;
    always @(posedge clk) if(image_mounted) begin
        // Limit to LBA28 and reject partial sectors/empty images.
        present <= image_size >= 512 && image_size[8:0] == 0;
        readonly <= image_readonly;
        capacity <= |image_size[63:37] ? 28'hfffffff : image_size[36:9];
    end

    reg [7:0] count, sector, cylinder_low, cylinder_high, device_head;
    reg [7:0] error_reg, control, bank;
    reg failed, pending_irq;
    reg [8:0] left;
    reg [27:0] current_lba;
    reg [7:0] word_index;
    reg previous_read, previous_write, data_read_active;
    wire channel = !bank[0];
    wire selected = channel && !device_head[4] && present;
    wire task_port = io_address >= 16'h0640 && io_address <= 16'h064e;
    wire control_port = io_address == 16'h074c || io_address == 16'h074e;
    wire bank_port = io_address == 16'h0430 || io_address == 16'h0432;
    wire decoded = !io_address[0] && io_select[0] && (task_port || control_port || bank_port);
    wire read_start = io_read && !previous_read && decoded;
    wire write_start = io_write && !previous_write && decoded;
    assign io_oe = decoded && io_read;
    assign irq = pending_irq && !control[1] && !control[2];

    // Transport has independent lifetime: a CPU/SRST reset drains an accepted
    // HPS transaction before another request can reuse the sector buffer.
    localparam H_IDLE=0, H_REQUEST=1, H_ACK=2;
    reg [1:0] host_state = H_IDLE;
    reg host_write = 0, host_done = 0;
    wire host_busy = host_state != H_IDLE || sd_ack;
    wire launch = !reset && !control[2] && !image_mounted && !host_busy &&
                  (state==READ_START || state==WRITE_START);
    assign sd_rd = host_state==H_REQUEST && !host_write;
    assign sd_wr = host_state==H_REQUEST && host_write;
    always @(posedge clk) begin
        host_done <= 0;
        case(host_state)
            H_IDLE: if(launch) begin
                sd_lba <= {4'b0,current_lba};
                host_write <= state==WRITE_START;
                host_state <= H_REQUEST;
            end
            H_REQUEST: if(sd_ack) host_state <= H_ACK;
            H_ACK: if(!sd_ack) begin host_state <= H_IDLE; host_done <= 1; end
            default: host_state <= H_IDLE;
        endcase
    end

    // CPU writes and host reads are separate command phases; likewise host
    // writes and CPU reads. Share the only RAM write port rather than asking
    // Quartus for two old-data write ports (which expanded 4 Kbits into LUTs).
    // Read-during-write values are deliberately unused by either consumer.
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] data_low[0:255], data_high[0:255];
    reg [7:0] cpu_low, cpu_high, host_low, host_high;
    reg host_byte;
    wire cpu_buffer_write = !reset && selected && !control[2] &&
        write_start && io_address==16'h0640 && state==WRITE_DATA;
    wire host_buffer_write = sd_buff_wr && sd_ack && host_busy && !host_write;
    wire [7:0] buffer_address = host_buffer_write ? sd_buff_addr[8:1] : word_index;
    always @(posedge clk) begin
        cpu_low <= data_low[buffer_address];
        cpu_high <= data_high[buffer_address];
        if(host_buffer_write) begin
            if(sd_buff_addr[0]) data_high[buffer_address] <= sd_buff_dout;
            else data_low[buffer_address] <= sd_buff_dout;
        end else if(cpu_buffer_write) begin
            data_low[buffer_address] <= io_writedata[7:0];
            // An 8-bit OUT consumes a word, with the unselected byte zero.
            data_high[buffer_address] <= io_select[1] ? io_writedata[15:8] : 8'b0;
        end
        host_low <= data_low[sd_buff_addr[8:1]];
        host_high <= data_high[sd_buff_addr[8:1]];
        host_byte <= sd_buff_addr[0];
    end
    assign sd_buff_din = host_byte ? host_high : host_low;

    wire [15:0] cylinders = |capacity[27:25] ? 16'hffff : capacity[24:9];
    function automatic [15:0] identify_word(input [7:0] index);
        begin
            case(index)
                0: identify_word=16'h0040; // Fixed ATA disk, no removable media.
                1,54: identify_word=cylinders;
                3,55: identify_word=16;
                6,56: identify_word=32;
                10: identify_word="Z9";
                11: identify_word="80";
                12: identify_word="00";
                13,14,15,16,17,18,19: identify_word="00";
                23: identify_word="00";
                24: identify_word="01";
                25,26: identify_word="  ";
                27: identify_word="Ze";
                28: identify_word="t9";
                29: identify_word="8 ";
                30: identify_word="ra";
                31: identify_word="w ";
                32: identify_word="di";
                33: identify_word="sk";
                34,35,36,37,38,39,40,41,42,43,44,45,46: identify_word="  ";
                49: identify_word=16'h0200; // LBA, no DMA.
                53: identify_word=1;
                57: identify_word={cylinders[6:0],9'b0};
                58: identify_word={7'b0,cylinders[15:7]};
                60: identify_word=capacity[15:0];
                61: identify_word={4'b0,capacity[27:16]};
                default: identify_word=0;
            endcase
        end
    endfunction
    wire busy = host_busy || state==READ_START || state==READ_WAIT ||
        state==WRITE_START || state==WRITE_WAIT || control[2];
    wire drq = state==READ_DATA || state==WRITE_DATA || state==IDENTIFY;
    wire [7:0] status = !selected ? 8'b0 : busy ? 8'h80 :
                        8'h50 | (drq ? 8'h08 : 8'h00) | {7'b0,failed};
    always @* begin
        io_readdata=16'hffff;
        case(io_address)
            16'h0430: io_readdata={8'hff,7'b0,present};
            16'h0432: io_readdata={8'hff,bank};
            16'h0640: if(selected && !busy) begin
                if(state==IDENTIFY) io_readdata=identify_word(word_index);
                else if(state==READ_DATA) io_readdata={cpu_high,cpu_low};
            end
            16'h0642: io_readdata={8'hff,selected ? error_reg : 8'hff};
            16'h0644: io_readdata={8'hff,count};
            16'h0646: io_readdata={8'hff,sector};
            16'h0648: io_readdata={8'hff,cylinder_low};
            16'h064a: io_readdata={8'hff,cylinder_high};
            16'h064c: io_readdata={8'hff,device_head};
            16'h064e,16'h074c: io_readdata={8'hff,status};
            16'h074e: io_readdata={8'hff,2'b11,~device_head[3:0],!device_head[4],device_head[4]};
            default: ;
        endcase
        if(!io_select[1]) io_readdata[15:8]=8'hff;
    end

    wire [27:0] requested_lba = device_head[6] ?
        {device_head[3:0],cylinder_high,cylinder_low,sector} :
        ({3'b0,cylinder_high,cylinder_low,device_head[3:0],5'b0} + {20'b0,sector} - 1'b1);
    wire [8:0] requested_count = count==0 ? 9'd256 : {1'b0,count};
    wire [28:0] requested_end = {1'b0,requested_lba} + requested_count;
    wire address_valid = (device_head[6] || (sector!=0 && sector<=32)) &&
                         requested_end <= {1'b0,capacity};
    task automatic abort_command(input [7:0] reason);
        begin state<=IDLE; failed<=1; error_reg<=reason; pending_irq<=1; end
    endtask
    task automatic advance_sector;
        begin
            current_lba<=current_lba+1'b1;
            left<=left-1'b1;
            count<=count-1'b1;
            if(device_head[6]) begin
                {device_head[3:0],cylinder_high,cylinder_low,sector}<=current_lba+1'b1;
            end else if(sector==32) begin
                sector<=1;
                device_head[3:0]<=device_head[3:0]+1'b1;
                if(device_head[3:0]==15) {cylinder_high,cylinder_low}<={cylinder_high,cylinder_low}+1'b1;
            end else sector<=sector+1'b1;
        end
    endtask
    always @(posedge clk) begin
        previous_read<=io_read;
        previous_write<=io_write;
        if(reset || image_mounted) begin
            state<=IDLE; count<=1; sector<=1; cylinder_low<=0; cylinder_high<=0;
            device_head<=8'ha0; bank<=0; control<=0; error_reg<=1; failed<=0;
            pending_irq<=0; word_index<=0; left<=0; current_lba<=0;
            previous_read<=0; previous_write<=0; data_read_active<=0;
        end else begin
            if(read_start && io_address==16'h064e && channel) pending_irq<=0;
            if(read_start && io_address==16'h0640 && selected && !busy &&
               (state==READ_DATA || state==IDENTIFY)) data_read_active<=1;
            // Change the read pointer only after the CPU has sampled/released
            // the bus. A held IN strobe never consumes multiple data words.
            if(!io_read && data_read_active) begin
                data_read_active<=0;
                word_index<=word_index+1'b1;
                if(word_index==255) begin
                    if(state==IDENTIFY) state<=IDLE;
                    else begin
                        advance_sector();
                        state<=left==1 ? IDLE : READ_START;
                    end
                end
            end
            if(cpu_buffer_write) begin
                word_index<=word_index+1'b1;
                if(word_index==255) state<=WRITE_START;
            end
            if(launch) state<=state==READ_START ? READ_WAIT : WRITE_WAIT;
            if(host_done && state==READ_WAIT) begin
                word_index<=0; state<=READ_DATA; pending_irq<=1;
            end
            if(host_done && state==WRITE_WAIT) begin
                advance_sector();
                word_index<=0; state<=left==1 ? IDLE : WRITE_DATA; pending_irq<=1;
            end
            if(write_start) begin
                if(io_address==16'h0432 && !io_writedata[7]) bank<=io_writedata[7:0]&8'h71;
                if(io_address==16'h074c && channel) begin
                    control<=io_writedata[7:0];
                    if(io_writedata[2] || control[2]) begin
                        state<=IDLE; pending_irq<=0; failed<=0; error_reg<=1;
                        count<=1; sector<=1; cylinder_low<=0; cylinder_high<=0;
                        device_head<=8'ha0; word_index<=0; data_read_active<=0;
                    end
                end
                if(channel && !busy && !control[2] && state==IDLE) case(io_address)
                    16'h0644: count<=io_writedata[7:0];
                    16'h0646: sector<=io_writedata[7:0];
                    16'h0648: cylinder_low<=io_writedata[7:0];
                    16'h064a: cylinder_high<=io_writedata[7:0];
                    16'h064c: device_head<=io_writedata[7:0];
                    16'h064e: if(selected && state==IDLE) begin
                        failed<=0; error_reg<=0; pending_irq<=0; word_index<=0;
                        current_lba<=requested_lba; left<=requested_count;
                        case(io_writedata[7:0])
                            8'hec: begin state<=IDENTIFY; pending_irq<=1; end
                            8'h20,8'h21,8'h30,8'h31,8'h40,8'h41:
                                if(!address_valid) abort_command(8'h10); // IDNF
                                else if((io_writedata[7:0]==8'h30 || io_writedata[7:0]==8'h31) && readonly)
                                    abort_command(8'h04);
                                else if(io_writedata[7:0]==8'h20 || io_writedata[7:0]==8'h21) state<=READ_START;
                                else if(io_writedata[7:0]==8'h30 || io_writedata[7:0]==8'h31) state<=WRITE_DATA;
                                else pending_irq<=1; // Verify range; host has no media-error return.
                            8'h10,8'h70,8'he7: pending_irq<=1; // Recalibrate, seek, flush (no write cache).
                            default: abort_command(8'h04); // Unsupported commands/features.
                        endcase
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
