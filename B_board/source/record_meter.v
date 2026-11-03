`timescale 1ns/1ps
// 15168 samples / 24 cells = 632 samples per cell. Use the capture count directly.
module record_meter(input wire [22:0] samples, output wire [4:0] remaining);
 wire [13:0] n=(samples>=23'd15168) ? 14'd0 : 14'd15168-samples[13:0];
 wire b4=n>=14'd10112; wire [13:0] r4=b4 ? n-14'd10112:n;
 wire b3=r4>=14'd5056; wire [13:0] r3=b3 ? r4-14'd5056:r4;
 wire b2=r3>=14'd2528; wire [13:0] r2=b2 ? r3-14'd2528:r3;
 wire b1=r2>=14'd1264; wire [13:0] r1=b1 ? r2-14'd1264:r2;
 wire b0=r1>=14'd632;
 assign remaining={b4,b3,b2,b1,b0};
endmodule
