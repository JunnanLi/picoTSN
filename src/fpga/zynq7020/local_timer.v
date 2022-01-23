/*
 *  picoTSN_hardware -- Hardware for picoTSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20 
 *  Description: Timer.
 *  Noted:
 *    |       |
 *    t0|-------------->|t1 = t0 + delay - offset
 *    |       |
 *    t3|<--------------|t2 = t3 - delay - offset;
 *    |       |
 *
 *    1) delay = (t3-t2+t1-t0)/2;
 *    2) offset = (t3-t2+t0-t1)/2;
 */


module local_timer(
  input                 clk,
  input                 rst_n,
  output  reg   [15:0]  local_time,

  //* 4 ports;
  input         [3:0]   update_time_valid,
  input         [255:0] update_time,

  //* signal every 2^16 clks?
  input                 time_int_i, //* all '0' or all '1';
  (* mark_debug = "true"*)output  reg           time_int_o,
  (* mark_debug = "true"*)output  reg           offset_time_valid_o,
  (* mark_debug = "true"*)output  reg   [11:0]  offset_time_o
);

//* each port has 4 timestamps, i.e., [0], [1], [2], [3];   
wire  [63:0]  update_time_w[3:0];
assign  {update_time_w[3],update_time_w[2],update_time_w[1],update_time_w[0]} = update_time;

//* update local time;
(* mark_debug = "true"*)reg   [15:0]  t0_sub_t1[3:0], t3_sub_t2[3:0];
(* mark_debug = "true"*)reg   [15:0]  temp_offset[3:0], offset[3:0];
(* mark_debug = "true"*)reg   [3:0]   temp_update_valid[2:0];

integer i;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    local_time            <= 16'b0;
    for(i=0; i<4; i=i+1) begin
      t0_sub_t1[i]        <= 16'b0;
      t3_sub_t2[i]        <= 16'b0;
      temp_offset[i]      <= 16'b0;
      offset[i]           <= 16'b0;
    end
    temp_update_valid[0]  <= 4'b0;
    temp_update_valid[1]  <= 4'b0;
    temp_update_valid[2]  <= 4'b0;
  end
  else begin
    local_time            <= local_time + 16'd1;
    for(i=0; i<4; i=i+1) begin
      //* update_time_valid is valid;
      t0_sub_t1[i]        <= update_time_w[i][(16*4-1):16*3] - update_time_w[i][(16*3-1):16*2];
      t3_sub_t2[i]        <= update_time_w[i][(16*1-1):0] - update_time_w[i][(16*2-1):16*1];
      //* temp_update_valid[0] is valid;
      temp_offset[i]      <= t0_sub_t1[i] + t3_sub_t2[i];
      //* temp_update_valid[1] is valid;
      offset[i]           <= {temp_offset[i][15],temp_offset[i][15:1]} + 16'd1;
    end

    {temp_update_valid[2],temp_update_valid[1],temp_update_valid[0]}  <= {temp_update_valid[1],
      temp_update_valid[0],update_time_valid};
    casez(temp_update_valid[2])
      4'b1???: local_time <= local_time + offset[3];
      4'b01??: local_time <= local_time + offset[2];
      4'b001?: local_time <= local_time + offset[1];
      4'b0001: local_time <= local_time + offset[0];
    endcase
  end
end

//* we scratch 16 times to get a true value:
//*   1) scratch 16 times -> scratch (all '0' or all '1') -> cur_time_i -> pre_time_int;
//*   2) if cur_time_i != pre_time_int, update offset_two_timer (according to cnt_time);
(* mark_debug = "true"*) reg  [15:0]  offset_two_timer, cnt_time;
(* mark_debug = "true"*) reg          pre_time_int_i, pre_time_int_o, cur_time_int_i, cur_time_int_o;
(* mark_debug = "true"*) reg  [15:0]  scratch_input, scratch_output;

//* for test;
(* mark_debug = "true"*) reg  [15:0]  cnt_time_input, cnt_time_output;
(* mark_debug = "true"*) reg          meet_cnt_bug,meet_cnt_bug_output;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    time_int_o          <= 4'b0;
    offset_two_timer    <= 16'b0;
    cnt_time            <= 16'b0;
    pre_time_int_i      <= 1'b0;
    pre_time_int_o      <= 1'b0;
    cur_time_int_i      <= 1'b0;
    cur_time_int_o      <= 1'b0;
    scratch_input       <= 16'b0;
    scratch_output      <= 16'b0;

    //*for test;
    cnt_time_input      <= 16'b0;
    cnt_time_output     <= 16'b0;
    meet_cnt_bug        <= 1'b0;
    meet_cnt_bug_output <= 1'b0;
  end
  else begin
    //* output time_int_o;
    time_int_o          <= (local_time == 16'b0)? ~time_int_o: time_int_o;
    //* scratch;
    scratch_input       <= {scratch_input[14:0],time_int_i};
    scratch_output      <= {scratch_output[14:0],time_int_o};
    //* get cur_time;
    cur_time_int_i      <= (scratch_input == 16'd0 || scratch_input == 16'hffff)? scratch_input[0]: cur_time_int_i;
    cur_time_int_o      <= (scratch_output == 16'd0 || scratch_output == 16'hffff)? scratch_output[0]: cur_time_int_o;
    //* get pre_time;
    pre_time_int_i      <= cur_time_int_i;
    pre_time_int_o      <= cur_time_int_o;
    //* update offset_two_timer;
    cnt_time            <= cnt_time + 16'd1;
    if(pre_time_int_i != cur_time_int_i || pre_time_int_o != cur_time_int_o) begin
      cnt_time          <= 16'b0;
      offset_two_timer  <= (cnt_time[15] == 1'b0)? cnt_time: ~cnt_time;
    end

    //* for test;
    cnt_time_input      <= (pre_time_int_i != cur_time_int_i)? 16'd0: (cnt_time_input + 16'd1);
    cnt_time_output     <= (pre_time_int_o != cur_time_int_o)? 16'd0: (cnt_time_output + 16'd1);

    if(pre_time_int_i != cur_time_int_i && cnt_time_input != 16'hffff)
      meet_cnt_bug      <= 1'b1;
    else
      meet_cnt_bug      <= 1'b0;

    if(pre_time_int_o != cur_time_int_o && cnt_time_output != 16'hffff)
      meet_cnt_bug_output   <= 1'b1;
    else
      meet_cnt_bug_output   <= 1'b0;

  end
end

//* output offset_time every 0.1s;
(* mark_debug = "true"*)reg   [9:0] cnt_time_cycle;
localparam  CNT_TO_OUTPUT = 10'd190;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    offset_time_valid_o       <= 1'b0;
    offset_time_o             <= 12'b0;
    cnt_time_cycle            <= 10'b0;
  end
  else begin
    offset_time_valid_o       <= 1'b0;
    if(update_time_valid != 4'b0) begin
      cnt_time_cycle          <= CNT_TO_OUTPUT - 10'd1;
    end
    else if(cnt_time == 16'b0) begin
      cnt_time_cycle          <= cnt_time_cycle + 10'd1;
      if(cnt_time_cycle == CNT_TO_OUTPUT) begin
        offset_time_valid_o   <= 1'b1;
        offset_time_o         <= offset_two_timer[11:0];
        cnt_time_cycle        <= 10'b0;
      end
    end
  end
end

endmodule
