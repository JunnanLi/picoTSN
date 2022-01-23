/*
 *  picoTSN_hardware -- Hardware for picoTSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20
 *  Description: add send timestamp for ptp packets, & change ptp type.
 *  Noted: 
 *    1) add recv timestamp for ptp packets (type = 0x0 & 0x1);
 *    2) format of fake pkt packet:
 *      ->  dmac: 0x00_01_02_03_04_05;
 *      ->  type: 0x00-0x03;
 *      ->  reserved: 0x00;
 *      ->  master_send_timestamp(t0): 0x00_00;
 *      ->  slaver_recv_timestamp(t1): 0x00_00;
 *      ->  slaver_send_timestamp(t2): 0x00_00;
 *      ->  master_recv_timestamp(t3): 0x00_00;
 *    3) parse ptp type:
 *      ->  0: from host, just add send timestamp;
 *      ->  1: from master, record send timestamp, add new recv/send timestamp;
 *      ->  2: from slaver, record recv/send timestamp, add new recv timestamp;
 *      ->  3: from master, record recv timestamp;
 */

`timescale 1ns / 1ps


module modify_packet(
  input               rst_n,
  input               clk,

  input               gmii_dv_i,
  input       [7:0]   gmii_data_i,
  input               gmii_er_i,

  output  reg [7:0]   gmii_data_o,
  output  reg         gmii_en_o,
  output  reg         gmii_er_o,
  input       [15:0]  local_time,
  output  reg [31:0]  cnt_pkt
);


//* read fifo for recving packet;
reg   [2:0]   state_modify;
reg   [3:0]   cnt_pkt_8B;
reg   [15:0]  local_time_reg;
localparam    IDLE_S              = 3'd0,
              WAIT_PKT_HEAD_S     = 3'd1,
              FAKE_PTP_PARSER_S   = 3'd2,
              FAKE_PTP_TPEY_S     = 3'd3,
              ADD_MSEND_ST_S      = 3'd4,
              ADD_SSEND_ST_S      = 3'd5,
              WAIT_TAIL_S         = 3'd6;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    gmii_er_o     <= 1'b0;
    gmii_data_o   <= 8'b0;
    gmii_en_o     <= 1'b0;
    cnt_pkt       <= 32'b0;
    cnt_pkt_8B    <= 4'b0;
    local_time_reg<= 16'b0;
    state_modify  <= IDLE_S;
  end
  else begin
    gmii_er_o     <= gmii_er_i;
    gmii_data_o   <= gmii_data_i;
    gmii_en_o     <= gmii_dv_i;

    case(state_modify)
      IDLE_S: begin
        if(gmii_dv_i == 1'b1) begin
          local_time_reg    <= local_time;
          cnt_pkt           <= cnt_pkt + 32'd1;
          state_modify      <= WAIT_PKT_HEAD_S;          
        end
        else begin
          state_modify      <= IDLE_S;
        end
      end
      WAIT_PKT_HEAD_S: begin
        if(gmii_data_i[7:0] == 8'hd5) begin
          cnt_pkt_8B        <= 4'b0;
          state_modify      <= FAKE_PTP_PARSER_S;
        end
        else begin
          state_modify      <= WAIT_PKT_HEAD_S;
        end
      end
      FAKE_PTP_PARSER_S: begin
        //* parse dmac;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        if(gmii_data_i[7:0] == {4'b0,cnt_pkt_8B}) begin
          //* dmac == 0x00_01_02_03_04_05
          if(cnt_pkt_8B == 4'd5)
            state_modify    <= FAKE_PTP_TPEY_S;
        end
        else //* normal pkt
          state_modify      <= WAIT_TAIL_S;
      end
      FAKE_PTP_TPEY_S: begin
        //* parse ptp type:
        //*   0: from host, just add send timestamp;
        //*   1: from master, record send timestamp, add new recv/send timestamp;
        //*   2: from slaver, record recv/send timestamp, add new recv timestamp;
        //*   3: from master, record recv timestamp;
        state_modify        <= WAIT_TAIL_S;
        if(gmii_data_i[1:0] == 2'd0) begin
          cnt_pkt_8B        <= 4'b0;
          state_modify      <= ADD_MSEND_ST_S;
        end
        else if(gmii_data_i[1:0] == 2'd1) begin
          cnt_pkt_8B        <= 4'b0;
          state_modify      <= ADD_SSEND_ST_S;
        end
        //* update ptp's type;
        gmii_data_o[2:0]    <= gmii_data_i[2:0] + 3'd1;

      end
      ADD_MSEND_ST_S: begin
        //* add send timestamp;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        gmii_data_o         <= (cnt_pkt_8B[1:0] == 2'd1)? local_time_reg[15:8]:
                                (cnt_pkt_8B[1:0] == 2'd2)? local_time_reg[7:0]: 
                                gmii_data_i[7:0];

        if(cnt_pkt_8B == 4'd2)
          state_modify      <= WAIT_TAIL_S;
      end
      ADD_SSEND_ST_S: begin
        //* add send timestamp;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        gmii_data_o         <= (cnt_pkt_8B[2:0] == 3'd5)? local_time_reg[15:8]:
                                (cnt_pkt_8B[2:0] == 3'd6)? local_time_reg[7:0]: 
                                gmii_data_i[7:0];

        if(cnt_pkt_8B == 4'd6)
          state_modify      <= WAIT_TAIL_S;
      end
      WAIT_TAIL_S: begin
        if(gmii_dv_i == 1'b0) begin //* end of one packet;
          state_modify      <= IDLE_S;
        end
        else begin
          state_modify      <= WAIT_TAIL_S; 
        end
      end
      default: begin
        state_modify       <= IDLE_S;
      end
    endcase
      
  end
end


endmodule
