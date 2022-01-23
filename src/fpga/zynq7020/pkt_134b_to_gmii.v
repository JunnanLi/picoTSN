/*
 *  picoTSN_hardware -- Hardware for TSN.
 *
 *  Copyright (C) 2021-2021 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Data: 2021.07.26
 *  Description: Divide 134b pkt into sixteen 8b gmii data.
 *  Noted:
 *    1) 134b pkt data definition: 
 *      [133:132] head tag, 2'b01 is head, 2'b10 is tail;
 *      [131:128] valid tag, 4'b1111 means sixteen 8b data is valid;
 *      [127:0]   pkt data, invalid part is padded with 0;
 *    2) req_bufferID_en & rden_pkt & ready_pkt is valid during one cycle;
 */

`timescale 1ns / 1ps

module pkt_134b_to_gmii(
  input                   rst_n,
  input                   clk,
  input                   empty_metadata,
  output  reg             rden_metadata,
  input         [15:0]    data_metadata,
  output  reg             req_bufferID_en,
  output  reg   [15:0]    req_bufferID,
  input                   ready_pkt,
  output  reg             rden_pkt,
  input         [133:0]   data_pkt,
  output  reg   [7:0]     gmii_data,
  output  reg             gmii_data_valid,
  output  reg   [31:0]    cnt_pkt
);

reg   [1:0] head_tag;             //* '01' is head, '10' is tail, '00' is body;
reg   [7:0] pkt_tag[15:0];        //* used to divide;
reg   [3:0] cnt_valid, cnt_gmii;  //* count of 8b data;
reg   [2:0] cnt_pktHead;          //* for '55' & 'd5';
reg   [3:0] state_div;
reg   [4:0] cnt_wait_clk;         //* 20 clk between two pkts;
localparam  IDLE_S          = 4'd0,
            WAIT_PKT_READY_S= 4'd1,
            PAD_PKT_TAG_S   = 4'd2,
            READ_PKT        = 4'd3,
            TRANS_PKT_S     = 4'd4,
            WAIT_S          = 4'd5;

integer i;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    gmii_data_valid         <= 1'b0;
    gmii_data               <= 8'b0;
    rden_metadata           <= 1'b0;
    req_bufferID_en         <= 1'b0;
    req_bufferID            <= 16'b0;
    rden_pkt                <= 1'b0;
    
    cnt_pkt                 <= 32'b0;
    cnt_gmii                <= 4'd0;
    cnt_wait_clk            <= 5'b0;
    cnt_pktHead             <= 3'b0;
    head_tag                <= 2'b0;
    for(i=0; i<16; i=i+1) begin
      pkt_tag[i]            <= 8'b0;
    end
    
    state_div               <= IDLE_S;
  end
  else begin
    cnt_gmii                <= 4'd1 + cnt_gmii;
    case(state_div)
      IDLE_S: begin
        rden_pkt            <= 1'b0;
        if(empty_metadata == 1'b0) begin
          rden_metadata     <= 1'b1;
          req_bufferID_en   <= 1'b1;
          req_bufferID      <= data_metadata;
          state_div         <= WAIT_PKT_READY_S;
        end
      end
      WAIT_PKT_READY_S: begin
        req_bufferID_en     <= 1'b0;
        rden_metadata       <= 1'b0;
        if(ready_pkt == 1'b1) begin
          cnt_pktHead       <= 3'b0;
          cnt_pkt           <= cnt_pkt + 32'd1;
          state_div         <= PAD_PKT_TAG_S;
        end
      end
      PAD_PKT_TAG_S: begin
        cnt_pktHead         <= cnt_pktHead + 3'd1;
        if(cnt_pktHead == 3'd7) begin
          gmii_data         <= 8'hd5;
          rden_pkt          <= 1'b1;
          state_div         <= READ_PKT;
        end
        else begin
          gmii_data         <= 8'h55;
        end
        gmii_data_valid     <= 1'b1;
      end
      READ_PKT: begin
        rden_pkt            <= 1'b0;
        {head_tag,cnt_valid,pkt_tag[0],pkt_tag[1],pkt_tag[2],
          pkt_tag[3],pkt_tag[4],pkt_tag[5],pkt_tag[6],pkt_tag[7],
          pkt_tag[8],pkt_tag[9],pkt_tag[10],pkt_tag[11],
          pkt_tag[12],pkt_tag[13],pkt_tag[14],pkt_tag[15]} <= data_pkt;
        cnt_gmii            <= 4'd0;
        
        gmii_data_valid     <= 1'b1;
        gmii_data           <= data_pkt[127:120];
        state_div           <= TRANS_PKT_S;
      end
      TRANS_PKT_S: begin
        (* full_case, parallel_case *)
        case(cnt_gmii)
          4'd0: gmii_data   <= pkt_tag[1];
          4'd1: gmii_data   <= pkt_tag[2];
          4'd2: gmii_data   <= pkt_tag[3];
          4'd3: gmii_data   <= pkt_tag[4];
          4'd4: gmii_data   <= pkt_tag[5];
          4'd5: gmii_data   <= pkt_tag[6];
          4'd6: gmii_data   <= pkt_tag[7];
          4'd7: gmii_data   <= pkt_tag[8];
          4'd8: gmii_data   <= pkt_tag[9];
          4'd9: gmii_data   <= pkt_tag[10];
          4'd10: gmii_data  <= pkt_tag[11];
          4'd11: gmii_data  <= pkt_tag[12];
          4'd12: gmii_data  <= pkt_tag[13];
          4'd13: gmii_data  <= pkt_tag[14];
          4'd14: gmii_data  <= pkt_tag[15];
          4'd15: gmii_data  <= pkt_tag[0];
        endcase
        
        cnt_gmii            <= cnt_gmii + 4'd1;
        cnt_valid           <= cnt_valid - 4'd1;
        gmii_data_valid     <= 1'b1;
        if(cnt_valid == 4'd0 && head_tag == 2'b10) begin
          gmii_data_valid   <= 1'b0;
          cnt_wait_clk      <= 5'd0;
          state_div         <= WAIT_S;
        end
        else if(cnt_valid == 4'd1 && head_tag != 2'b10) begin
          rden_pkt          <= 1'b1;
          state_div         <= READ_PKT;
        end
      end
      WAIT_S: begin
        cnt_wait_clk        <= 5'd1 + cnt_wait_clk;
        if(cnt_wait_clk == 5'd12) state_div <= IDLE_S;
        else                      state_div <= WAIT_S;
      end
      default: begin
        state_div           <= IDLE_S;
      end
    endcase
    
  end
end



//* cnt_pkt for test;
(* mark_debug = "true"*)reg   [31:0]  cnt_meta_pkt2gmii;
(* mark_debug = "true"*)reg   [31:0]  cnt_gmii_pkt2gmii;
(* mark_debug = "true"*)reg   [31:0]  cnt_pktHead_pkt2gmii;
reg temp_gmii_valid;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    cnt_meta_pkt2gmii       <= 32'b0;
    cnt_gmii_pkt2gmii       <= 32'b0;
    cnt_pktHead_pkt2gmii    <= 32'b0;
    temp_gmii_valid         <= 1'b0;
  end
  else begin
    if(rden_metadata == 1'b1)
      cnt_meta_pkt2gmii     <= cnt_meta_pkt2gmii + 32'd1;
    temp_gmii_valid         <= gmii_data_valid;
    if(temp_gmii_valid == 1'b1 && gmii_data_valid == 1'b0)
      cnt_gmii_pkt2gmii     <= cnt_gmii_pkt2gmii + 32'd1;
    if(rden_pkt == 1'b1 && data_pkt[133:132] == 2'b01 && gmii_data == 8'hd5)
      cnt_pktHead_pkt2gmii  <= cnt_pktHead_pkt2gmii + 32'd1;
  end
end



endmodule
