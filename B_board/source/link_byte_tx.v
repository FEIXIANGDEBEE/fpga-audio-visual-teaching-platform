module link_byte_tx(input clk,input rst_n,input clear,input [7:0] data,input valid,output ready,output reg done,
 output reg [7:0] f_data,output reg f_clk,output reg f_valid,input f_ready,output reg [31:0] hold_cycles,output reg [31:0] timeouts);
 reg meta,sync;always @(posedge clk)if(!rst_n || clear)begin meta<=0;sync<=0;end else begin meta<=f_ready;sync<=meta;end
 reg [2:0] state;reg [7:0] held;reg [25:0] wait_count;
 assign ready=state==0 && !sync;
 always @(posedge clk)begin
 if(!rst_n || clear)begin state<=0;held<=0;done<=0;f_data<=0;f_clk<=0;f_valid<=0;hold_cycles<=0;timeouts<=0;wait_count<=0;end
 else begin done<=0;case(state)
 0:if(valid && !sync)begin held<=data;state<=1;end
 1:begin f_data<=held;state<=2;end
 2:begin f_clk<=~f_clk;f_valid<=1;wait_count<=0;state<=3;end
 3:if(sync)begin f_valid<=0;state<=4;end else begin hold_cycles<=hold_cycles+1'b1;if(wait_count==49999999)begin timeouts<=timeouts+1'b1;wait_count<=0;end else wait_count<=wait_count+1'b1;end
 4:if(!sync)begin done<=1;state<=0;end
 endcase end end
endmodule
