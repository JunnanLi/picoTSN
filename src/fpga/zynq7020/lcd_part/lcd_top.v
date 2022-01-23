/*
 *  vga_hardware -- Hardware for vga.
 *
 *  Please communicate with Junnan Li <lijunnan@nudt.edu.cn> when meeting any question.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last update date: 2022.01.19
 *  Description: teris_top. 
 */

module lcd(
  input                 core_clk,       //* pico clock
  input         [11:0]  core_dis_data,
  input                 core_dis_data_wr,
  input                 sys_clk,        //* pixel clock
  input                 rst,            //* reset signal high active
  output reg            hs,             //* horizontal synchronization
  output reg            vs,             //* vertical synchronization
  output reg            de,             //* video valid
  output wire   [7:0]   rgb_r,          //* video red data
  output wire   [7:0]   rgb_g,          //* video green data
  output wire   [7:0]   rgb_b           //* video blue data
);


wire  [11:0]  active_x, active_y; // video x,y position
wire  [11:0]  v_cnt, h_cnt;
wire          hs_syn, vs_syn;
wire          video_active; // video active(horizontal active and vertical active)
wire          temp_bit;

//* delay 1 sys_clk;
always@(posedge sys_clk or posedge rst) begin
  if(rst == 1'b1)
    begin
      hs <= 1'b0;
      vs <= 1'b0;
      de <= 1'b0;
    end
  else
    begin
      hs <= hs_syn;
      vs <= vs_syn;
      de <= video_active;
    end
end

//* obtain distance;
(* mark_debug = "true"*)reg           rden_dis_data;
(* mark_debug = "true"*)wire          empty_dis_data;
(* mark_debug = "true"*)wire  [11:0]  dout_dis_data;
(* mark_debug = "true"*)reg   [11:0]  distance;
(* mark_debug = "true"*)reg           distance_valid;
reg   [1:0]   state_dis;
(* mark_debug = "true"*)wire  [15:0]  distance_bcd;
(* mark_debug = "true"*)wire          distance_valid_bcd;
(* mark_debug = "true"*)wire          b_to_bcd_ready;
localparam    IDLE_S        = 2'd0,
              RD_DATA_S     = 2'd1,
              WAIT_1_CLK_S  = 2'd2;

always@(posedge sys_clk or posedge rst) begin
  if(rst == 1'b1) begin
    distance                  <= 12'b0;
    distance_valid            <= 1'b0;
    rden_dis_data             <= 1'b1;

    state_dis                 <= IDLE_S;
  end
  else begin
    case(state_dis)
      IDLE_S: begin
        if(empty_dis_data == 1'b0 && b_to_bcd_ready == 1'b1) begin
          rden_dis_data       <= 1'b1;
          state_dis           <= RD_DATA_S;
        end
      end
      RD_DATA_S: begin
        rden_dis_data         <= 1'b0;
        distance              <= dout_dis_data;
        distance_valid        <= 1'b1;
        state_dis             <= WAIT_1_CLK_S;
      end
      WAIT_1_CLK_S: begin
        distance_valid        <= 1'b0;
        state_dis             <= IDLE_S;
      end
      default: begin
      end
    endcase
  end
end

asfifo_12b_512 asfifo_distance_data(
  .rst(rst),
  .wr_clk(core_clk),
  .rd_clk(sys_clk),
  .din(core_dis_data),
  .wr_en(core_dis_data_wr),
  .rd_en(rden_dis_data),
  .dout(dout_dis_data),
  .full(),
  .empty(empty_dis_data)
);

binary_to_bcd b_to_bcd(
  .clk(sys_clk),
  .rst(rst),
  .bin_in_valid(distance_valid),
  .bin_in(distance),
  .bcd_out(distance_bcd),
  .bcd_out_valid(distance_valid_bcd),
  .ready(b_to_bcd_ready)
);

//* judege whether current 28*15 sub-block(16*16) is empty? (temp_bit = '0'?) 
lcd_array lcdArray(
  .clk(sys_clk),
  .rst(rst),
  .h_cnt(h_cnt),
  .v_cnt(v_cnt),
  .active_x(active_x),
  .active_y(active_y),
  .distance(distance_bcd),
  .distance_valid(distance_valid_bcd),
  .temp_bit(temp_bit)
);

//* output rgb line by line;
hdmi_output hdmi_o(
  .clk(sys_clk),
  .rst(rst),
  .hs_reg(hs_syn),
  .vs_reg(vs_syn),
  .video_active(video_active),
  .rgb_r_reg(rgb_r),
  .rgb_g_reg(rgb_g),
  .rgb_b_reg(rgb_b),
  .active_x(active_x),
  .active_y(active_y),
  .h_cnt(h_cnt),
  .v_cnt(v_cnt),
  .temp_bit(temp_bit) 
);

endmodule 