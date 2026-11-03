`timescale 1ns/1ps
// Feed the CRC-qualified remote byte stream into the aspect-fit scaler.
// 640x480 selects identity geometry on the same decoder and FIFO.
module scene_bmp_stream #(parameter TIMEOUT_CYCLES=250000000)(
 input wire clk,rst_n,start,abort,input wire [31:0] file_bytes,
 input wire byte_valid,input wire [7:0] byte_data,output wire byte_ready,
 output wire pixel_valid,output wire [23:0] pixel_data,input wire pixel_ready,
 output reg done,fault,output reg [7:0] error_code,
 output reg [15:0] source_width,source_height,
 output reg [31:0] raw_bytes,output wire [31:0] raw_crc,
 output wire [31:0] filled_rows,fallback_count,dropped_bytes,
 output wire [18:0] target_pixels,
 output wire [351:0] header_diagnostics,
 output wire [37:0] actual_fit
);
 `include "crc32_defs.vh"
 localparam IDLE=0,HEADER=1,CHECK=2,ARM=3,DATA=4,DRAIN=5,FAILED=6;
 reg [2:0] state;reg [5:0] index;reg [31:0] held_size,timer,crc;
 // Register the next timeout predicate with the counter. At the decision
 // edge it equals timer>=TIMEOUT_CYCLES-1; an already-due timeout still wins
 // over progress arriving on that edge.
 reg timeout_due;
 reg [15:0] signature,planes,bpp;
 reg [31:0] bmp_size,offset,dib_size,width,height,compression,image_size;
 reg start_engine,eof;
 wire eng_ready,eng_done;
 // The scaler consumes each in_valid pulse. Pulse it only for accepted
 // remote bytes, since the upstream stream can wait.
 wire eng_valid=state==DATA && !start_engine && byte_valid && eng_ready;
 assign byte_ready=state==HEADER || (state==DATA && !start_engine && eng_ready);
 wire eng_pixel_valid;
 // ARM asserts start_engine before the scaler clears its prior out_v.
 // Mask launch, HEADER and IDLE output, including abort/restart.
 assign pixel_valid=(state==DATA || state==DRAIN) && !start_engine && eng_pixel_valid;
 assign raw_crc=~crc;
 wire [10:0] row_words=({2'b0,width[10:2]}+{1'b0,width[10:2],1'b0})+{9'b0,width[1:0]};
 wire [21:0] image_words=row_words*height[10:0];
 wire [31:0] computed_bytes={8'd0,image_words,2'b0};
 wire header_ok=signature==16'h4d42 && offset==54 && dib_size==40 && bmp_size==held_size &&
  width>=1 && width<=2047 && height>=1 && height<=2047 && planes==1 && bpp==24 &&
  compression==0 && image_size!=0 && image_size==computed_bytes && bmp_size==54+image_size;
 wire [11:0] header_guards={signature==16'h4d42,offset==54,dib_size==40,bmp_size==held_size,
  width>=1 && width<=2047,height>=1 && height<=2047,planes==1,bpp==24,
  compression==0,image_size!=0,image_size==computed_bytes,bmp_size==54+image_size};
 wire [31:0] finish_diagnostics={fallback_count!=0,dropped_bytes!=0,filled_rows!={16'd0,source_height},
  raw_bytes!=image_size,target_pixels==307200,filled_rows[10:0],state,done,header_guards};
 assign header_diagnostics={computed_bytes,finish_diagnostics,signature,planes,bpp,7'd0,state,index,
  bmp_size,offset,dib_size,width,height,image_size,held_size};
 // Keep input upstream until ready; this interface can apply backpressure.
 scale_engine_v2 #(.ASPECT_FIT(1),.ELASTIC_INPUT(1),.FIFO_AW(10)) scaler(.clk(clk),.rst(!rst_n),.start(start_engine),
  .src_w(source_width),.src_h(source_height),.in_valid(eng_valid),.in_data(byte_data),
  .in_ready(eng_ready),.pause(),.file_eof(eof),.out_valid(eng_pixel_valid),.out_data(pixel_data),
  .out_ready(pixel_ready && pixel_valid),.busy(),.frame_done(eng_done),.dest_cnt_o(target_pixels),
  .fallback_count(fallback_count),.filled_rows(filled_rows),.dropped_bytes(dropped_bytes),.actual_fit(actual_fit));
 task fail;input [7:0] code;
  begin fault<=1;done<=0;error_code<=code;state<=FAILED;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;index<=0;held_size<=0;timer<=0;timeout_due<=TIMEOUT_CYCLES<=1;crc<=32'hffffffff;
   signature<=0;planes<=0;bpp<=0;bmp_size<=0;offset<=0;dib_size<=0;
   width<=0;height<=0;compression<=0;image_size<=0;start_engine<=0;eof<=0;
   done<=0;fault<=0;error_code<=0;source_width<=0;source_height<=0;raw_bytes<=0;
  end else if(abort)begin state<=IDLE;start_engine<=0;eof<=0;done<=0;fault<=0;end
  else begin
   start_engine<=0;
   if(state!=IDLE && state!=FAILED && !done)begin
    if((byte_valid && byte_ready) || (pixel_valid && pixel_ready))begin timer<=0;timeout_due<=TIMEOUT_CYCLES<=1;end
    else begin timer<=timer+1'b1;timeout_due<=TIMEOUT_CYCLES<=1 || timer>=TIMEOUT_CYCLES-2;end
   end
   case(state)
    IDLE:if(start)begin
     held_size<=file_bytes;index<=0;timer<=0;timeout_due<=TIMEOUT_CYCLES<=1;crc<=32'hffffffff;raw_bytes<=0;
     signature<=0;planes<=0;bpp<=0;bmp_size<=0;offset<=0;dib_size<=0;width<=0;height<=0;compression<=0;image_size<=0;
     done<=0;fault<=0;error_code<=0;eof<=0;
     if(file_bytes<54 || file_bytes>67108864)fail(8'h01);else state<=HEADER;
    end
    HEADER:if(byte_valid && byte_ready)begin
     index<=index+1'b1;
     case(index)
      0,1:signature[index*8 +:8]<=byte_data;
      2,3,4,5:bmp_size[(index-2)*8 +:8]<=byte_data;
      10,11,12,13:offset[(index-10)*8 +:8]<=byte_data;
      14,15,16,17:dib_size[(index-14)*8 +:8]<=byte_data;
      18,19,20,21:width[(index-18)*8 +:8]<=byte_data;
      22,23,24,25:height[(index-22)*8 +:8]<=byte_data;
      26,27:planes[(index-26)*8 +:8]<=byte_data;
      28,29:bpp[(index-28)*8 +:8]<=byte_data;
      30,31,32,33:compression[(index-30)*8 +:8]<=byte_data;
      34,35,36,37:image_size[(index-34)*8 +:8]<=byte_data;
     endcase
     if(index==53)state<=CHECK;
    end
    CHECK:begin
     if(!header_ok)fail(8'h02);
     else begin source_width<=width[15:0];source_height<=height[15:0];state<=ARM;end
    end
    ARM:begin start_engine<=1;state<=DATA;end
    DATA:if(byte_valid && byte_ready)begin
     raw_bytes<=raw_bytes+1'b1;crc<=crc32_byte(crc,byte_data);
     if(raw_bytes==image_size-1)begin eof<=1;state<=DRAIN;end
    end
    DRAIN:if(eng_done && target_pixels==307200 && !pixel_valid)begin
     if(raw_bytes!=image_size || filled_rows!={16'd0,source_height} || fallback_count!=0 || dropped_bytes!=0)fail(8'h03);
     else begin done<=1;state<=IDLE;end
    end
   endcase
   if(state!=IDLE && state!=FAILED && !done && timeout_due)fail(8'h04);
  end
 end
endmodule
