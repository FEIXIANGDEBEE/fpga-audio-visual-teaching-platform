`timescale 1ns/1ps
`include "ui_protocol.vh"
`include "text_a_defs.vh"
module tb;
 reg clk=0,rst=0,cv=0;reg[7:0] cmd=0;reg[351:0] status=0;
 wire av;wire[7:0] op,val;wire[127:0] view;reg ack=0;reg[7:0] aop=0;integer got=0;reg[7:0] seen;
 always #10 clk=~clk;
 menu_control dut(.clk(clk),.rst_n(rst),.ms_tick(1'b0),.key_id(5'd0),.key_flags(3'd0),.key_valid(1'b0),
 .short_key(4'd0),.long_key(4'd0),.switches(4'd0),.command(cmd),.command_valid(cv),.demo_prepare(1'b0),
 .online(1'b1),.status_valid(1'b1),.status(status),.current_page(4'd3),.current_valid(1'b1),.local_busy(1'b0),.local_fault(1'b0),
 .action_valid(av),.action_ready(1'b1),.action_op(op),.action_value(val),.result_valid(ack),.result(8'd0),.view(view),.result_op(aop));
 always @(negedge clk)begin ack=av && op!=`UI_CONTEXT;aop=op;if(av && op==`UI_VIEW)begin got=got+1;seen=val;status[295]=val==3;end end
 task key;input[7:0] c;begin @(negedge clk);#1;cmd=c;cv=1;@(negedge clk);#1;cv=0;repeat(6)@(negedge clk);end endtask
 reg[127:0] testview=0;reg[9:0] x=433;wire direct;wire[8:0] glyph;wire[7:0] line;
 osd_layout layout(.x(x),.y(10'd161),.de(1'b1),.rgb(24'd0),.view(testview),.switches(4'd0),.page(4'd3),.brightness(3'd2),.contrast(3'd2),.effect(2'd2),.direct(direct),.glyph(glyph),.line(line));
 initial begin
  status[237]=1;status[292]=1;repeat(3)@(negedge clk);rst=1;repeat(5)@(negedge clk);
  key("o");key(")");key(")");key(")");key("=");key("=");
  if(view[5:3]!=3 || view[2:0]!=3)$fatal(1,"menu navigation %h",view);
  key(">");if(seen!=1)$fatal(1,"history");key(">");if(seen!=2)$fatal(1,"wave");key(">");if(seen!=3)$fatal(1,"eco");
  key(">");if(seen!=3)$fatal(1,"upper bound");key("<");if(seen!=2)$fatal(1,"wake wave");key("<");key("<");if(seen!=0)$fatal(1,"spectrum");key("<");if(seen!=0)$fatal(1,"lower bound");
  testview[2:0]=2;testview[5:3]=3;testview[99]=1;#1;if(direct || line!=`A_UI_SPECTRUM)$fatal(1,"normal label");
  testview[58]=1;#1;if(direct || line!=`A_UI_WAVE || layout.xx!=257)$fatal(1,"eco shared label tail");x=450;#1;if(layout.xx!=274)$fatal(1,"eco label next glyph");
  $display("MENU_PASS remote navigation four views bounds true-status eco glyphs actions=%0d",got);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
