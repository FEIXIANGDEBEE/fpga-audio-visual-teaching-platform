function [31:0] crc32_byte;
 input [31:0] crc;input [7:0] value;
 integer k;reg [31:0] c;
 begin c=crc^{24'd0,value};for(k=0;k<8;k=k+1)c=c[0] ? (c>>1)^32'hedb88320 : c>>1;crc32_byte=c;end
endfunction
