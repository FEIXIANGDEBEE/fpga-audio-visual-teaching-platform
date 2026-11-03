`timescale 1ns/1ps

// Latch effects at the first active pixel and hold through the frame.
// Use the video reader's committed pixel-domain ID to bind those controls.
module video_fx #(
    parameter integer FADE_FRAMES = 8,
    parameter [7:0] DEFAULT_BRIGHTNESS = 8'd255,
    parameter [7:0] DEFAULT_CONTRAST = 8'd128,
    parameter OSD_DEFAULT_ENABLE = 1'b1,
    parameter integer STATUS_X=32, STATUS_Y=40, STATUS_SCALE_LOG2=1,
    // ARITH_MODE: 0 general arithmetic; 1 shared-DSP presets; 2 exact shift/add.
    parameter integer EXTERNAL_OSD=0,PRESET_ONLY=0,FRAME_AT_ACTIVE=0
) (
    input wire clk, rst_n,
    input wire in_hs, in_vs, in_de,
    input wire [9:0] pixel_x, pixel_y,
    input wire [23:0] rgb_in,
    input wire [31:0] frame_id,
    input wire [7:0] brightness_cfg, contrast_cfg,
    input wire osd_enable_cfg, status_live,
    output wire out_hs, out_vs, out_de,
    output wire [23:0] rgb_out,
    output wire [7:0] brightness_active, contrast_active,
    output wire fade_active,
    output wire osd_active
);
    localparam integer FADE_W = (FADE_FRAMES < 2) ? 1 : $clog2(FADE_FRAMES + 1);
    localparam integer FADE_STEP = (FADE_FRAMES > 0) ? (256 / FADE_FRAMES) : 256;
    reg [7:0] brightness_q, contrast_q;
    reg osd_q;
    reg [31:0] id_q;
    reg [FADE_W-1:0] fade_q;
    reg fade_valid_q;
    // Debounce holds the control bundle across many link clocks. Sample it
    // twice in the pixel domain before committing at frame_start.
    (* ASYNC_REG="TRUE" *) reg [7:0] brightness_m, brightness_s;
    (* ASYNC_REG="TRUE" *) reg [7:0] contrast_m, contrast_s;
    (* ASYNC_REG="TRUE" *) reg osd_m, osd_s;
    wire frame_start = in_de && pixel_x == 10'd0 && pixel_y == 10'd0;
    wire [7:0] fade_alpha = (FADE_FRAMES == 0 || fade_q >= FADE_FRAMES) ?
                            8'd255 : fade_q * FADE_STEP;

    function [7:0] sat8;
        input integer value;
        begin
            if (value < 0) sat8 = 8'd0;
            else if (value > 255) sat8 = 8'd255;
            else sat8 = value[7:0];
        end
    endfunction

    function [7:0] brightness_apply;
        input [7:0] value,level;
        reg [15:0] product;
        reg [10:0] five_value;reg [8:0] boosted;
        begin
            // 253=9/8 and 254=5/4 brightness presets; saturation precedes truncation.
            boosted={1'b0,value}+(level==253 ? {4'd0,value[7:3]}:{3'd0,value[7:2]});
            if(level==253 || level==254)brightness_apply=boosted[8] ? 8'd255:boosted[7:0];
            else if(PRESET_ONLY==2)begin
                // Exact four-preset arithmetic: 160/256=5/8, 128/256=1/2.
                five_value={1'b0,value,2'b00}+{3'b000,value};
                brightness_apply=level==128 ? {1'b0,value[7:1]} : level==160 ? five_value[10:3] : value;
            end else begin
                product=value*level;
                brightness_apply=level==255 ? value : product[15:8];
            end
        end
    endfunction

    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar = value < 10 ? ("0" + value) : ("A" + value - 10); end
    endfunction

    function [7:0] contrast_apply;
        input [7:0] value;
        input [7:0] contrast;
        integer signed centered;
        integer signed scaled;
        reg [7:0] fraction;
        reg signed [9:0] adjusted;
        begin
            if(PRESET_ONLY==2)begin
                // floor(3*(v-128)/2)+128 = v+floor(v/2)-64.
                // floor(5*(v-128)/4)+128 = v+floor(v/4)-32.
                // The shared 10-bit sum spans -64..318; its upper two bits select saturation.
                fraction=contrast==192 ? {1'b0,value[7:1]} : {2'b00,value[7:2]};
                adjusted=$signed({2'b00,value})+$signed({2'b00,fraction})-
                         (contrast==192 ? 10'sd64 : 10'sd32);
                if(contrast!=192 && contrast!=160) contrast_apply=value;
                else if(adjusted[9]) contrast_apply=8'd0;
                else if(adjusted[8]) contrast_apply=8'd255;
                else contrast_apply=adjusted[7:0];
            end else begin
                centered = value;
                centered = centered - 128;
                scaled = (centered * $signed({1'b0, contrast})) >>> 7;
                contrast_apply = sat8(scaled + 128);
            end
        end
    endfunction

    function [4:0] glyph;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph = 5'b0;
            case (ch)
                "0": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b10011;3:glyph=5'b10101;4:glyph=5'b11001;5:glyph=5'b10001;6:glyph=5'b01110; endcase
                "1": case(row) 0:glyph=5'b00100;1:glyph=5'b01100;2:glyph=5'b00100;3:glyph=5'b00100;4:glyph=5'b00100;5:glyph=5'b00100;6:glyph=5'b01110; endcase
                "2": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b00001;3:glyph=5'b00010;4:glyph=5'b00100;5:glyph=5'b01000;6:glyph=5'b11111; endcase
                "3": case(row) 0:glyph=5'b11110;1:glyph=5'b00001;2:glyph=5'b00001;3:glyph=5'b01110;4:glyph=5'b00001;5:glyph=5'b00001;6:glyph=5'b11110; endcase
                "4": case(row) 0:glyph=5'b00010;1:glyph=5'b00110;2:glyph=5'b01010;3:glyph=5'b10010;4:glyph=5'b11111;5:glyph=5'b00010;6:glyph=5'b00010; endcase
                "5": case(row) 0:glyph=5'b11111;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b11110;4:glyph=5'b00001;5:glyph=5'b00001;6:glyph=5'b11110; endcase
                "6": case(row) 0:glyph=5'b01110;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b11110;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b01110; endcase
                "7": case(row) 0:glyph=5'b11111;1:glyph=5'b00001;2:glyph=5'b00010;3:glyph=5'b00100;4:glyph=5'b01000;5:glyph=5'b01000;6:glyph=5'b01000; endcase
                "8": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b01110;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b01110; endcase
                "9": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b01111;4:glyph=5'b00001;5:glyph=5'b00001;6:glyph=5'b01110; endcase
                "A": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b11111;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b10001; endcase
                "B": case(row) 0:glyph=5'b11110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b11110;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b11110; endcase
                "C": case(row) 0:glyph=5'b01111;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b10000;4:glyph=5'b10000;5:glyph=5'b10000;6:glyph=5'b01111; endcase
                "E": case(row) 0:glyph=5'b11111;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b11110;4:glyph=5'b10000;5:glyph=5'b10000;6:glyph=5'b11111; endcase
                "F": case(row) 0:glyph=5'b11111;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b11110;4:glyph=5'b10000;5:glyph=5'b10000;6:glyph=5'b10000; endcase
                ":": case(row) 2:glyph=5'b00100;4:glyph=5'b00100; endcase
                "D": case(row) 0:glyph=5'b11110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b10001;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b11110; endcase
                "I": case(row) 0:glyph=5'b11111;1:glyph=5'b00100;2:glyph=5'b00100;3:glyph=5'b00100;4:glyph=5'b00100;5:glyph=5'b00100;6:glyph=5'b11111; endcase
                "L": case(row) 0:glyph=5'b10000;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b10000;4:glyph=5'b10000;5:glyph=5'b10000;6:glyph=5'b11111; endcase
                "M": case(row) 0:glyph=5'b10001;1:glyph=5'b11011;2:glyph=5'b10101;3:glyph=5'b10101;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b10001; endcase
                "O": case(row) 0:glyph=5'b01110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b10001;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b01110; endcase
                "P": case(row) 0:glyph=5'b11110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b11110;4:glyph=5'b10000;5:glyph=5'b10000;6:glyph=5'b10000; endcase
                "R": case(row) 0:glyph=5'b11110;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b11110;4:glyph=5'b10100;5:glyph=5'b10010;6:glyph=5'b10001; endcase
                "S": case(row) 0:glyph=5'b01111;1:glyph=5'b10000;2:glyph=5'b10000;3:glyph=5'b01110;4:glyph=5'b00001;5:glyph=5'b00001;6:glyph=5'b11110; endcase
                "T": case(row) 0:glyph=5'b11111;1:glyph=5'b00100;2:glyph=5'b00100;3:glyph=5'b00100;4:glyph=5'b00100;5:glyph=5'b00100;6:glyph=5'b00100; endcase
                "U": case(row) 0:glyph=5'b10001;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b10001;4:glyph=5'b10001;5:glyph=5'b10001;6:glyph=5'b01110; endcase
                "V": case(row) 0:glyph=5'b10001;1:glyph=5'b10001;2:glyph=5'b10001;3:glyph=5'b10001;4:glyph=5'b10001;5:glyph=5'b01010;6:glyph=5'b00100; endcase
                "X": case(row) 0:glyph=5'b10001;1:glyph=5'b10001;2:glyph=5'b01010;3:glyph=5'b00100;4:glyph=5'b01010;5:glyph=5'b10001;6:glyph=5'b10001; endcase
                "-": case(row) 3:glyph=5'b11111; endcase
                default: glyph=5'b0;
            endcase
        end
    endfunction

    function [7:0] osd_char;
        input integer index;
        input [31:0] id;
        input [7:0] brightness;
        input [7:0] contrast;
        begin
            case (index)
                0:osd_char="D"; 1:osd_char="1"; 2:osd_char="5"; 3:osd_char=" ";
                4:osd_char="I"; 5:osd_char="D"; 6:osd_char=":";
                7:osd_char=hexchar(id[31:28]); 8:osd_char=hexchar(id[27:24]);
                9:osd_char=hexchar(id[23:20]); 10:osd_char=hexchar(id[19:16]);
                11:osd_char=hexchar(id[15:12]); 12:osd_char=hexchar(id[11:8]);
                13:osd_char=hexchar(id[7:4]); 14:osd_char=hexchar(id[3:0]); 15:osd_char=" ";
                16:osd_char="B"; 17:osd_char=":";
                18:osd_char=hexchar(brightness[7:4]); 19:osd_char=hexchar(brightness[3:0]);
                20:osd_char="C"; 21:osd_char=":";
                22:osd_char=hexchar(contrast[7:4]); 23:osd_char=hexchar(contrast[3:0]);
                24:osd_char=" ";
                25:osd_char=status_live ? "L" : "S";
                26:osd_char=status_live ? "I" : "T";
                27:osd_char=status_live ? "V" : "O";
                28:osd_char=status_live ? "E" : "P";
                29:osd_char=" ";
                default:osd_char=" ";
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brightness_q <= DEFAULT_BRIGHTNESS;
            contrast_q <= DEFAULT_CONTRAST;
            osd_q <= OSD_DEFAULT_ENABLE;
            id_q <= 32'd0;
            fade_q <= FADE_FRAMES;
            fade_valid_q <= 1'b0;
            brightness_m <= DEFAULT_BRIGHTNESS;
            brightness_s <= DEFAULT_BRIGHTNESS;
            contrast_m <= DEFAULT_CONTRAST;
            contrast_s <= DEFAULT_CONTRAST;
            osd_m <= OSD_DEFAULT_ENABLE;
            osd_s <= OSD_DEFAULT_ENABLE;
        end else begin
            brightness_m <= brightness_cfg;
            brightness_s <= brightness_m;
            contrast_m <= contrast_cfg;
            contrast_s <= contrast_m;
            osd_m <= osd_enable_cfg;
            osd_s <= osd_m;
            if (FRAME_AT_ACTIVE ? frame_start : (pixel_x == 0 && pixel_y == 480)) begin
                brightness_q <= brightness_s;
                contrast_q <= contrast_s;
                osd_q <= osd_s;
            end
            if (frame_start) begin
              if (frame_id != id_q) begin
                id_q <= frame_id;
                fade_q <= 0;
                fade_valid_q <= FADE_FRAMES != 0;
              end else if (fade_valid_q && fade_q < FADE_FRAMES) begin
                fade_q <= fade_q + 1'b1;
                if (fade_q + 1'b1 >= FADE_FRAMES)
                    fade_valid_q <= 1'b0;
              end else begin
                fade_valid_q <= 1'b0;
              end
            end
        end
    end

    integer fade_r, fade_g, fade_b;
    integer ci, cx, cy;
    reg [7:0] ch;
    reg [4:0] bits;
    reg [23:0] processed_rgb, overlay_rgb;
    reg overlay_pixel;
    always @* begin
        fade_r = fade_alpha == 255 ? rgb_in[23:16] : (rgb_in[23:16] * fade_alpha) >>> 8;
        fade_g = fade_alpha == 255 ? rgb_in[15:8] : (rgb_in[15:8] * fade_alpha) >>> 8;
        fade_b = fade_alpha == 255 ? rgb_in[7:0] : (rgb_in[7:0] * fade_alpha) >>> 8;
        processed_rgb = {brightness_apply(contrast_apply(sat8(fade_r), contrast_q),brightness_q),
                         brightness_apply(contrast_apply(sat8(fade_g), contrast_q),brightness_q),
                         brightness_apply(contrast_apply(sat8(fade_b), contrast_q),brightness_q)};
        overlay_rgb = processed_rgb;
        overlay_pixel = 1'b0;
        ci = (pixel_x < STATUS_X) ? -1 : (pixel_x - STATUS_X) >> (3+STATUS_SCALE_LOG2);
        cx = ((pixel_x - STATUS_X) >> STATUS_SCALE_LOG2) & 7;
        cy = (pixel_y - STATUS_Y) >> STATUS_SCALE_LOG2;
        ch = " "; bits = 5'b0;
        if (!EXTERNAL_OSD && osd_q && in_de && pixel_y >= STATUS_Y-4 &&
            pixel_y < STATUS_Y+(8<<STATUS_SCALE_LOG2)+4 &&
            pixel_x >= STATUS_X-4 && pixel_x < STATUS_X+(30<<(3+STATUS_SCALE_LOG2))+4)
            overlay_rgb={2'b00,processed_rgb[23:18],2'b00,processed_rgb[15:10],2'b00,processed_rgb[7:2]};
        if (!EXTERNAL_OSD && osd_q && in_de && pixel_y >= STATUS_Y && pixel_y < STATUS_Y+(7<<STATUS_SCALE_LOG2) &&
            pixel_x >= STATUS_X && ci < 30 && cx < 5) begin
            ch = osd_char(ci, id_q, brightness_q, contrast_q);
            bits = glyph(ch, cy[2:0]);
            overlay_pixel = bits[4-cx];
        end
        if (overlay_pixel) overlay_rgb = 24'hffffff;
    end

    assign out_hs = in_hs;
    assign out_vs = in_vs;
    assign out_de = in_de;
    wire [23:0] subtitle_rgb;
    generate if(EXTERNAL_OSD)begin:g_external_subtitles
     assign subtitle_rgb=overlay_rgb;
    end else begin:g_legacy_subtitles
    subtitle_overlay subtitle(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .enable(osd_q && !EXTERNAL_OSD),.de(in_de),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .rgb_in(overlay_rgb),.rgb_out(subtitle_rgb),.text_pixel(),.band_pixel());
    end endgenerate
    assign rgb_out = in_de ? subtitle_rgb : 24'h000000;
    assign brightness_active = brightness_q;
    assign contrast_active = contrast_q;
    assign fade_active = fade_valid_q;
    assign osd_active = osd_q;
endmodule
