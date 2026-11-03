`timescale 1ns/1ps
// Evaluate symmetric2 L1 DTW serially over 16 dimensions. All references
// have 32 frames, giving the same N+32 denominator. Compare class costs
// directly and share one multiplier for threshold and margin checks.
// Hold the input utterance until done or abort.
module voice_dtw(
 input wire clk,rst_n,start,abort,input wire [6:0] length,start_frame,
 output wire [10:0] utterance_address,input wire [7:0] utterance_data,
 output reg busy,done,accepted,output reg [7:0] command,
 output reg [17:0] best_cost,output reg [7:0] best_denominator,
 output reg [31:0] cycles
);
 `include "voice_model.vh"
 localparam [17:0] INF=18'h3ffff;
 localparam IDLE=0,INIT=1,CELL_ADDR=2,CELL_WAIT=3,DIM_LOAD=4,DIM_WAIT=5,DIM_ADD=6,
  CELL_WRITE=7,TEMPLATE_DONE=8,SELECT=9,DECIDE=10,FINISH=11,SELECT_SECOND=12,DECIDE_MARGIN=13;
 reg [3:0] state,template_id;reg [6:0] n,utterance_length,first_frame;reg [5:0] m;
 reg [3:0] dimension;reg bank;reg [5:0] init_index;reg below_threshold;
 reg [17:0] left,diagonal,above;reg [10:0] distance;
 reg [17:0] class_cost[0:2];wire [7:0] class_den[0:2];
 reg [1:0] selected,best_class,second_class;reg [17:0] final_cost;
 wire [7:0] denominator={1'b0,utterance_length}+8'd32;
 assign class_den[0]=denominator;assign class_den[1]=denominator;assign class_den[2]=denominator;
 wire [1:0] current_class=template_id<5 ? 0 : template_id<10 ? 1 : 2;
 wire [6:0] read_frame=first_frame+n-1'b1;
 assign utterance_address={read_frame,dimension};
 wire [12:0] rom_address={template_id,m[4:0]-5'd1,dimension};
 wire [7:0] rom_data;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
  .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("voice_templates.dath")) templates(
  .doa(rom_data),.dob(),.dia(8'd0),.dib(8'd0),.cea(1'b1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
  .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(rom_address),.addrb(13'd0));
 wire row_write=state==INIT || state==CELL_WRITE;
 wire [6:0] row_write_address=state==INIT ? {1'b0,init_index} : {bank,m};
 wire [18:0] c_up={1'b0,above}+distance,c_left={1'b0,left}+distance,c_diag={1'b0,diagonal}+{distance,1'b0};
 wire [18:0] minimum=c_up<c_left ? (c_up<c_diag ? c_up:c_diag) : (c_left<c_diag ? c_left:c_diag);
 wire [17:0] cell_cost=minimum>=INF ? INF:minimum[17:0];
 wire [17:0] row_write_data=state==INIT ? (init_index==0 ? 18'd0:INF) : cell_cost;
 wire [17:0] row_data;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(18),.DATA_WIDTH_B(18),.ADDR_WIDTH_A(7),.ADDR_WIDTH_B(7),
  .DATA_DEPTH_A(128),.DATA_DEPTH_B(128),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) rows(
  .doa(),.dob(row_data),.dia(row_write_data),.dib(18'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
  .clka(clk),.clkb(clk),.wea(row_write),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(row_write_address),.addrb({!bank,m}));
 wire signed [8:0] difference=$signed({utterance_data[7],utterance_data})-$signed({rom_data[7],rom_data});
 wire [8:0] absolute_difference=difference[8] ? -difference:difference;
 wire [7:0] selected_command={6'd0,best_class}+1'b1;
 wire [15:0] factor=state==DECIDE ? command_threshold(selected_command[1:0]):command_margin(selected_command[1:0]);
 wire [23:0] decision_product=factor*denominator;
 wire [17:0] score_gap=class_cost[second_class]-class_cost[best_class];
 integer i;
 // Cancel stops ownership and decisions. Reinitialize these operands before
 // the next use; their update control does not need the wide cancellation cone.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   init_index<=0;
   for(i=0;i<3;i=i+1)class_cost[i]<=INF;
  end else begin
   if(state==IDLE && start && length!=0 && length<=96)begin
    init_index<=0;
    for(i=0;i<3;i=i+1)class_cost[i]<=INF;
   end else begin
    if(state==INIT && init_index!=32)init_index<=init_index+1'b1;
    if(state==TEMPLATE_DONE)begin
     if(final_cost<class_cost[current_class])class_cost[current_class]<=final_cost;
     if(template_id!=V25_TEMPLATE_COUNT-1)init_index<=0;
    end
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;template_id<=0;n<=0;m<=0;utterance_length<=0;first_frame<=0;dimension<=0;bank<=1;below_threshold<=0;
   left<=INF;diagonal<=0;above<=0;distance<=0;selected<=0;best_class<=0;second_class<=1;final_cost<=0;
   busy<=0;done<=0;accepted<=0;command<=0;best_cost<=0;best_denominator<=1;cycles<=0;
  end else begin
   done<=0;
   if(busy)cycles<=cycles+1'b1;
   if(abort)begin state<=IDLE;busy<=0;accepted<=0;end
   else case(state)
    IDLE:if(start && length!=0 && length<=96)begin
     busy<=1;accepted<=0;command<=0;utterance_length<=length;first_frame<=start_frame;
     template_id<=0;state<=INIT;bank<=1;cycles<=0;
      end
    INIT:if(init_index==32)begin n<=1;m<=1;dimension<=0;left<=INF;diagonal<=0;state<=CELL_ADDR;end

    CELL_ADDR:begin dimension<=0;distance<=0;state<=CELL_WAIT;end
    CELL_WAIT:begin above<=row_data;state<=DIM_LOAD;end
    DIM_LOAD:state<=DIM_WAIT;
    DIM_WAIT:state<=DIM_ADD;
    DIM_ADD:begin
     distance<=distance+absolute_difference;
     if(dimension==15)state<=CELL_WRITE;
     else begin dimension<=dimension+1'b1;state<=DIM_LOAD;end
    end
    CELL_WRITE:begin
     left<=cell_cost;diagonal<=above;
     if(m==32)begin
      if(n==utterance_length)begin final_cost<=cell_cost;state<=TEMPLATE_DONE;end
      else begin n<=n+1'b1;m<=1;bank<=!bank;left<=INF;diagonal<=INF;state<=CELL_ADDR;end
     end else begin m<=m+1'b1;state<=CELL_ADDR;end
    end
    TEMPLATE_DONE:begin
     if(template_id==V25_TEMPLATE_COUNT-1)begin selected<=1;best_class<=0;second_class<=1;state<=SELECT;end
     else begin template_id<=template_id+1'b1;bank<=1;state<=INIT;end
    end
    SELECT:begin
     if(class_cost[selected]<class_cost[best_class])begin
      second_class<=best_class;best_class<=selected;
      if(selected==2)state<=DECIDE;else selected<=selected+1'b1;
     end else if(selected==1)begin second_class<=selected;selected<=2;end
     else state<=SELECT_SECOND;
    end
    SELECT_SECOND:begin
     if(class_cost[selected]<class_cost[second_class])second_class<=selected;
     state<=DECIDE;
    end
    DECIDE:begin
     best_cost<=class_cost[best_class];best_denominator<=denominator;command<=selected_command;
     below_threshold<=class_cost[best_class]<=decision_product;
     state<=DECIDE_MARGIN;
    end
    DECIDE_MARGIN:begin
     accepted<=below_threshold && class_cost[second_class]>=class_cost[best_class] &&
       score_gap>=decision_product && utterance_length>=command_minimum(selected_command[1:0]);
     state<=FINISH;
    end
    FINISH:begin done<=1;busy<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
