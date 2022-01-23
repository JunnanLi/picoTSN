/*
 *  picoTSN_hardware -- Hardware for picoTSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20
 *  Description: Asynchronous recving packets.
 *  Noted: 
 *    1) Since two packets will be merged into one while reading 
 *      speed is slower than writing speed, we use [8](b) to distinguish,
 *      e.g., any two packets insert one data whose [8](b) is '0';
 *    2) add recv timestamp for ptp packets (type = 0x1 & 0x2);
 *    3) format of fake pkt packet:
 *      ->  dmac: 0x00_01_02_03_04_05;
 *      ->  type: 0x00-0x03;
 *      ->  reserved: 0x00;
 *      ->  master_send_timestamp(t0): 0x00_00;
 *      ->  slaver_recv_timestamp(t1): 0x00_00;
 *      ->  slaver_send_timestamp(t2): 0x00_00;
 *      ->  master_recv_timestamp(t3): 0x00_00;
 *    4) parse ptp type:
 *      ->  0: from host, just add send timestamp;
 *      ->  1: from master, record send timestamp, add new recv/send timestamp;
 *      ->  2: from slaver, record recv/send timestamp, add new recv timestamp;
 *      ->  3: from master, record recv timestamp;
 */

`timescale 1ns / 1ps


module asyn_recv_packet(
  input               rst_n,
  input               gmii_rx_clk,
  input       [7:0]   gmii_rxd,
  input               gmii_rx_dv,
  input               gmii_rx_er,
  input               clk_125m,
  output  reg [7:0]   gmii_txd,
  output  reg         gmii_tx_en,
  output  reg         gmii_tx_er,
  input       [15:0]  local_time,
  (* mark_debug = "true"*)output  reg         update_time_valid,
  (* mark_debug = "true"*)output  reg [63:0]  update_time,
  
  output  reg [31:0]  cnt_pkt
);


reg         temp_gmii_rx_dv;
reg   [8:0] din_recv_fifo_9b;
reg         wren_recv_fifo_1b;
reg         rden_recv_fifo_1b;
wire  [8:0] dout_recv_fifo_9b; 
wire        empty_recv_fifo_1b;

//* write fifo;
always @(posedge gmii_rx_clk or negedge rst_n) begin
  if(!rst_n) begin
    din_recv_fifo_9b    <= 9'b0;
    wren_recv_fifo_1b   <= 1'b0;
    temp_gmii_rx_dv     <= 1'b0;
  end
  else begin
    temp_gmii_rx_dv     <= gmii_rx_dv;
    if(gmii_rx_dv == 1'b1) begin
      wren_recv_fifo_1b <= 1'b1;
      din_recv_fifo_9b  <= {1'b1,gmii_rxd};
    end
    else if(temp_gmii_rx_dv == 1'b1) begin
      wren_recv_fifo_1b <= 1'b1;
      din_recv_fifo_9b  <= 9'b0;
    end
    else begin
      wren_recv_fifo_1b <= 1'b0;
    end
  end
end

//* read fifo for recving packet;
(* mark_debug = "true"*)reg   [2:0]   state_rd;
(* mark_debug = "true"*)reg   [3:0]   cnt_pkt_8B;
//* for test
(* mark_debug = "true"*)reg   [3:0]   state_ptp;
reg   [15:0]  local_time_reg;
localparam    IDLE_S              = 3'd0,
              DISCARD_PKT_HEAD_S  = 3'd1,
              FAKE_PTP_PARSER_S   = 3'd2,
              FAKE_PTP_TPEY_S     = 3'd3,
              ADD_MRECV_ST_S      = 3'd4,
              ADD_SRECV_ST_S      = 3'd5,
              GET_TIME_INFO_S     = 3'd6,
              WAIT_TAIL_S         = 3'd7;

always @(posedge clk_125m or negedge rst_n) begin
  if(!rst_n) begin
    gmii_tx_er    <= 1'b0;
    gmii_txd      <= 8'b0;
    gmii_tx_en    <= 1'b0;
    cnt_pkt       <= 32'b0;
    cnt_pkt_8B    <= 4'b0;
    local_time_reg<= 16'b0;
    state_rd      <= IDLE_S;

    //* for test;
    state_ptp     <= 4'b0;
  end
  else begin
    case(state_rd)
      IDLE_S: begin
        if(empty_recv_fifo_1b == 1'b0) begin
          local_time_reg    <= local_time;
          cnt_pkt           <= cnt_pkt + 32'd1;
          rden_recv_fifo_1b <= 1'b1;
          state_rd          <= DISCARD_PKT_HEAD_S;          
        end
        else begin
          rden_recv_fifo_1b <= 1'b0;
          state_rd          <= IDLE_S;
        end
      end
      DISCARD_PKT_HEAD_S: begin
        if(dout_recv_fifo_9b[7:0] == 8'hd5) begin
          cnt_pkt_8B        <= 4'b0;
          state_rd          <= FAKE_PTP_PARSER_S;
        end
        else begin
          state_rd          <= DISCARD_PKT_HEAD_S;
        end
      end
      FAKE_PTP_PARSER_S: begin
        //* output gmii;
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];

        //* parse dmac;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        if(dout_recv_fifo_9b[7:0] == {4'b0,cnt_pkt_8B}) begin
          //* dmac == 0x00_01_02_03_04_05
          if(cnt_pkt_8B == 4'd5)
            state_rd        <= FAKE_PTP_TPEY_S;
        end
        else //* normal pkt
          state_rd          <= WAIT_TAIL_S;
      end
      FAKE_PTP_TPEY_S: begin
        //* output gmii;
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];

        //* parse ptp type:
        //*   0: from host, just add send timestamp;
        //*   1: from master, record send timestamp, add new recv/send timestamp;
        //*   2: from slaver, record recv/send timestamp, add new recv timestamp;
        //*   3: from master, record recv timestamp;
        state_rd            <= WAIT_TAIL_S;
        if(dout_recv_fifo_9b[1:0] == 2'd1) begin
          cnt_pkt_8B        <= 4'b0;
          state_rd          <= ADD_SRECV_ST_S;
        end
        else if(dout_recv_fifo_9b[1:0] == 2'd2) begin
          cnt_pkt_8B        <= 4'b0;
          state_rd          <= ADD_MRECV_ST_S;
        end
        else if(dout_recv_fifo_9b[1:0] == 2'd3) begin
          cnt_pkt_8B        <= 4'b0;
          state_rd          <= GET_TIME_INFO_S;
        end

        //* for test;
        state_ptp[0]        <= (dout_recv_fifo_9b[1:0] == 2'd0)? ~state_ptp[0]: state_ptp[0];
        state_ptp[1]        <= (dout_recv_fifo_9b[1:0] == 2'd1)? ~state_ptp[1]: state_ptp[1];
        state_ptp[2]        <= (dout_recv_fifo_9b[1:0] == 2'd2)? ~state_ptp[2]: state_ptp[2];
        state_ptp[3]        <= (dout_recv_fifo_9b[1:0] == 2'd3)? ~state_ptp[3]: state_ptp[3];
      end
      ADD_SRECV_ST_S: begin
        //* output gmii;
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];

        //* add recv timestamp;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        gmii_txd            <= (cnt_pkt_8B[2:0] == 3'd3)? local_time_reg[15:8]:
                                (cnt_pkt_8B[2:0] == 3'd4)? local_time_reg[7:0]: 
                                dout_recv_fifo_9b[7:0];

        if(cnt_pkt_8B == 4'd4)
          state_rd          <= WAIT_TAIL_S;
      end
      ADD_MRECV_ST_S: begin
        //* output gmii;
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];

        //* add recv timestamp;
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        gmii_txd            <= (cnt_pkt_8B[3:0] == 4'd7)? local_time_reg[15:8]:
                                (cnt_pkt_8B[3:0] == 4'd8)? local_time_reg[7:0]: 
                                dout_recv_fifo_9b[7:0];

        if(cnt_pkt_8B == 4'd8)
          state_rd          <= WAIT_TAIL_S;
      end
      GET_TIME_INFO_S: begin
        //* output gmii;
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];

        //* accumulate update_time
        cnt_pkt_8B          <= 4'd1 + cnt_pkt_8B;
        if(cnt_pkt_8B[3:0] != 4'd0)
          update_time       <= {update_time[55:0],dout_recv_fifo_9b[7:0]};
        if(cnt_pkt_8B == 4'd8) begin
          update_time_valid <= 1'b1;
          state_rd          <= WAIT_TAIL_S;
        end
      end
      WAIT_TAIL_S: begin
        gmii_txd            <= dout_recv_fifo_9b[7:0];
        gmii_tx_en          <= dout_recv_fifo_9b[8];
        update_time_valid   <= 1'b0;
        
        if(dout_recv_fifo_9b[8] == 1'b0) begin //* end of one packet;
          rden_recv_fifo_1b <= 1'b0;
          state_rd          <= IDLE_S;
        end
        else begin
          state_rd          <= WAIT_TAIL_S; 
        end
      end
      default: begin
        state_rd            <= IDLE_S;
      end
    endcase
      
  end
end

asfifo_9_1024 asfifo_recv_data(
  .rst(!rst_n),
  .wr_clk(gmii_rx_clk),
  .rd_clk(clk_125m),
  .din(din_recv_fifo_9b),
  .wr_en(wren_recv_fifo_1b),
  .rd_en(rden_recv_fifo_1b),
  .dout(dout_recv_fifo_9b),
  .full(),
  .empty(empty_recv_fifo_1b)
);


endmodule
