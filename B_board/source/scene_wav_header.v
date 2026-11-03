`timescale 1ns/1ps
// Read metadata by byte address and skip payloads. Validate the entire
// RIFF chunk list before publishing a descriptor.
module scene_wav_header #(parameter MAX_FILE_BYTES=67108864)(
    input wire clk,rst_n,start,input wire [31:0] file_bytes,
    output wire byte_req,output wire [31:0] byte_offset,
    input wire byte_valid,input wire [7:0] byte_data,input wire byte_error,
    output reg done,error,output reg [7:0] error_code,
    output reg stereo,output wire [31:0] data_offset,data_bytes,track_frames
);
    localparam IDLE=0,RIFF=1,RIFF_CHECK=2,CHUNK=3,CHUNK_CHECK=4,FMT=5,FMT_CHECK=6,NEXT=7,HALT=8;
    reg [3:0] state;
    reg [5:0] index;
    reg [31:0] shift;
    wire [31:0] riff_size=shift,chunk_size=shift;
    reg id_fmt,id_data;
    localparam POS_W=$clog2(MAX_FILE_BYTES+1);
    reg [POS_W-1:0] position,bound,next_chunk;
    reg [POS_W-1:0] published_offset,published_bytes;
    reg [POS_W-2:0] published_frames;
    assign data_offset=published_offset;
    assign data_bytes=published_bytes;
    assign track_frames=published_frames;
    reg signature_ok,format_ok,format_stereo;
    reg [7:0] signature_byte,format_byte;
    reg seen_fmt,seen_data;
    wire [32:0] riff_end={1'b0,riff_size}+33'd8;
    wire [POS_W:0] payload_low={1'b0,position}+{1'b0,chunk_size[POS_W-1:0]}+chunk_size[0];
    wire payload_out_of_bounds=(chunk_size>>POS_W)!=0 || payload_low>{1'b0,bound};
    always @* begin
        case(index)
            0:signature_byte="R";1:signature_byte="I";2,3:signature_byte="F";
            8:signature_byte="W";9:signature_byte="A";10:signature_byte="V";11:signature_byte="E";default:signature_byte=0;
        endcase
        case(index)
            0:format_byte=1;
            2:format_byte=0; // channels 1/2 is checked separately
            4:format_byte=8'h80;5:format_byte=8'hbb;
            8:format_byte=format_stereo ? 8'h00 : 8'h00;
            9:format_byte=format_stereo ? 8'hee : 8'h77;
            10:format_byte=format_stereo ? 8'h02 : 8'h01;
            12:format_byte=format_stereo ? 4 : 2;
            14:format_byte=16;
            default:format_byte=0;
        endcase
    end
    assign byte_offset=position;
    assign byte_req=state==RIFF || state==CHUNK || state==FMT;
    task reject;
        input [7:0] code;
        begin state<=HALT;error<=1;error_code<=code;done<=0;end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;index<=0;shift<=0;signature_ok<=0;id_fmt<=0;id_data<=0;
            bound<=0;next_chunk<=0;format_ok<=0;format_stereo<=0;seen_fmt<=0;seen_data<=0;
            position<=0;done<=0;error<=0;error_code<=0;stereo<=0;published_offset<=0;published_bytes<=0;published_frames<=0;
        end else if(byte_error && byte_req)reject(8'h06);
        else case(state)
            IDLE: if(start)begin
                done<=0;error<=0;error_code<=0;seen_fmt<=0;seen_data<=0;position<=0;index<=0;shift<=0;signature_ok<=1;
                if(file_bytes<12 || file_bytes>MAX_FILE_BYTES)reject(8'h02);else state<=RIFF;
            end
            RIFF:if(byte_valid)begin
                if(index>=4 && index<8)shift<={byte_data,shift[31:8]};
                position<=position+1'b1;index<=index+1'b1;
                if(index<4 || index>=8)signature_ok<=signature_ok && byte_data==signature_byte;
                if(index==11)state<=RIFF_CHECK;
            end
            RIFF_CHECK:begin
                if(!signature_ok)reject(8'h01);
                else if(riff_end!={1'b0,file_bytes})reject(8'h02);
                else begin bound<=file_bytes;state<=NEXT;end
            end
            NEXT:begin
                if(position==bound)begin
                    if(seen_fmt && seen_data)begin done<=1;state<=HALT;end else reject(8'h05);
                end else if({1'b0,position}+8>{1'b0,bound})reject(8'h02);
                else begin index<=0;shift<=0;id_fmt<=1;id_data<=1;state<=CHUNK;end
            end
            CHUNK:if(byte_valid)begin
                if(index>=4)shift<={byte_data,shift[31:8]};
                else case(index)
                    0:begin id_fmt<=id_fmt && byte_data=="f";id_data<=id_data && byte_data=="d";end
                    1:begin id_fmt<=id_fmt && byte_data=="m";id_data<=id_data && byte_data=="a";end
                    2:begin id_fmt<=id_fmt && byte_data=="t";id_data<=id_data && byte_data=="t";end
                    3:begin id_fmt<=id_fmt && byte_data==" ";id_data<=id_data && byte_data=="a";end
                endcase
                position<=position+1'b1;index<=index+1'b1;
                if(index==7)state<=CHUNK_CHECK;
            end
            CHUNK_CHECK:begin
                if(payload_out_of_bounds)reject(8'h02);
                else begin
                    next_chunk<=payload_low[POS_W-1:0];
                    if(id_fmt)begin
                        if(seen_fmt || seen_data)reject(8'h04);
                        else if(chunk_size!=16 && chunk_size!=18)reject(8'h03);
                        else begin format_ok<=1;format_stereo<=0;index<=0;state<=FMT;end
                    end else if(id_data)begin
                        if(!seen_fmt || seen_data)reject(8'h04);
                        else if(chunk_size==0 || (stereo ? chunk_size[1:0]!=0 : chunk_size[0]!=0))reject(8'h03);
                        else begin seen_data<=1;published_offset<=position;published_bytes<=chunk_size[POS_W-1:0];
                            published_frames<=stereo ? chunk_size>>2 : chunk_size>>1;position<=payload_low[POS_W-1:0];state<=NEXT;end
                    end else begin position<=payload_low[POS_W-1:0];state<=NEXT;end
                end
            end
            FMT:if(byte_valid)begin
                if(index==2)begin format_stereo<=byte_data==2;format_ok<=format_ok && (byte_data==1 || byte_data==2);end
                else format_ok<=format_ok && byte_data==format_byte;
                position<=position+1'b1;index<=index+1'b1;
                if(index==chunk_size-1)state<=FMT_CHECK;
            end
            FMT_CHECK:begin
                if(!format_ok)reject(8'h03);
                else begin stereo<=format_stereo;seen_fmt<=1;position<=next_chunk;state<=NEXT;end
            end
            HALT:if(!start)state<=IDLE;
            default:reject(8'h07);
        endcase
    end
endmodule
