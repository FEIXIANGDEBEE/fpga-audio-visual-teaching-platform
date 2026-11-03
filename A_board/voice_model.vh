// Generated from frozen model; edit model/exporter instead.
localparam [31:0] V25_MODEL_CRC=32'h83b9807b;
localparam V25_TEMPLATE_COUNT=15;
localparam V25_TEMPLATE_FRAMES=32;
function [6:0] template_length;
input [3:0] index;
begin case(index)
0:template_length=7'd32;
1:template_length=7'd32;
2:template_length=7'd32;
3:template_length=7'd32;
4:template_length=7'd32;
5:template_length=7'd32;
6:template_length=7'd32;
7:template_length=7'd32;
8:template_length=7'd32;
9:template_length=7'd32;
10:template_length=7'd32;
11:template_length=7'd32;
12:template_length=7'd32;
13:template_length=7'd32;
14:template_length=7'd32;
default:template_length=0;
endcase end
endfunction
function [15:0] command_threshold;
input [1:0] index;
begin case(index)
1:command_threshold=16'd191;
2:command_threshold=16'd106;
3:command_threshold=16'd148;
default:command_threshold=0;
endcase end
endfunction
function [15:0] command_margin;
input [1:0] index;
begin case(index)
1:command_margin=16'd18;
2:command_margin=16'd11;
3:command_margin=16'd14;
default:command_margin=0;
endcase end
endfunction
function [6:0] command_minimum;
input [1:0] index;
begin case(index)
1:command_minimum=7'd22;
2:command_minimum=7'd18;
3:command_minimum=7'd29;
default:command_minimum=0;
endcase end
endfunction
