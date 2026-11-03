`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg[9:0] x=0,y=0;reg de=0;reg[127:0] view=0;wire active,direct,overlay;wire[7:0] line;wire[9:0] xx;wire[5:0] yy;wire[1:0] size;wire[8:0] glyph;wire[23:0] bg,ink,rgb;wire od;
 osd_layout layout(x,y,de,24'h203040,view,4'd0,4'd3,3'd2,3'd2,2'd2,overlay,active,direct,line,xx,yy,size,glyph,bg,ink);
 text_engine text(clk,1'b1,1'b0,1'b0,de,bg,ink,active,line,xx,yy,size,direct,glyph,,,od,rgb);
 integer f,i,j,pixels=0;reg capture=0;
 always @(negedge clk)if(capture && od)begin $fwrite(f,"%06x\n",rgb);pixels=pixels+1;end
 initial begin
  f=$fopen("menu_pixels.hex","w");view[2:0]=3;view[5:3]=3;view[99]=1;view[80]=1;view[58]=1;view[12:9]=3;
  repeat(5)@(negedge clk);#1;capture=1;
  for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin @(negedge clk);#1;x=i;y=j;de=1;end
  @(negedge clk);#1;de=0;repeat(6)@(negedge clk);#1;
  if(pixels!=307200)$fatal(1,"raster length %0d",pixels);$fclose(f);$display("MENU_PIXELS_PASS full production text raster 640x480");$finish;
 end
endmodule
