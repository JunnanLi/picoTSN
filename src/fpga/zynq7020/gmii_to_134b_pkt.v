/*
 *  picoTSN_hardware -- Hardware for TSN.
 *
 *  Copyright (C) 2021-2021 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Data: 2021.08.21
 *  Description: accumulate sixteen 8b gmii data into 134b pkt & 
 *                output a metadata.
 *  Noted:
 *    1) 134b pkt data definition: 
 *      [133:132] head tag, 2'b01 is head, 2'b10 is tail;
 *      [131:128] valid tag, 4'b1111 means sixteen 8b data is valid;
 *      [127:0]   pkt data, invalid part is padded with 0;
 *    2) 128b metadata:
 *      [55:48]   pktType;
 *        [55]    '1' is ptp;
 *        [54:51] reserved;
 *        [50:48] ptp type;
 *      [47:40]   inPort;
 *      [39:32]   outPort;
 *      [31:24]   dstMAC[7:0];
 *      [23:16]   srcMAC[7:0];
 *      [15:0]    bufferID:
 *        [15:14] used to distinguish which port;
 *        [13:0]  bufferID, max bufferID: 2^14 for each port;
 */

`timescale 1ns / 1ps
// `def OPEN_COUNTER  //* for test;

module gmii_to_134b_pkt #(parameter PORT_NUM = 8'd0)(
  input               rst_n,
  input               clk,
  input       [7:0]   gmii_data,
  input               gmii_data_valid,
  //* to buffer;
  output  reg [133:0] pkt_data,
  output  reg         pkt_data_valid,
  //* to lookup;
  output  reg [127:0] metadata,
  output  reg         metadata_valid,
  //* from buffer;
  input       [15:0]  bufferID
);

reg   [1:0] head_tag;       //* '01' is head, '10' is tail, '00' is body;
reg   [7:0] pkt_tag[15:0];  //* used to accumulate;
reg   [3:0] cnt_valid;      //* count of 8b data;
reg   [7:0] cnt_16B;        //* count of 16B data, should be small than 2KB;
reg   [3:0] state_accu;
localparam  IDLE_S          = 4'd0,
            WAIT_TAIL_S     = 4'd1,
            OVERFLOW_S      = 4'd2;
//* cnt_discard_gmii2pkt for test;
`ifdef OPEN_COUNTER
  (* mark_debug = "true"*)reg   [31:0]  cnt_discard_gmii2pkt;
  (* mark_debug = "true"*)reg   [31:0]  cnt_meta_gmii2pkt;
`endif

integer i;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    pkt_data_valid          <= 1'b0;
    pkt_data                <= 134'b0;
    cnt_valid               <= 4'b0;
    head_tag                <= 2'b0;
    cnt_16B                 <= 8'b0;
    state_accu              <= IDLE_S;
    `ifdef
      cnt_discard_gmii2pkt  <= 32'd0;
    `endif

    for(i=0; i<16; i=i+1) begin
      pkt_tag[i]            <= 8'b0;
    end
  end
  else begin
    case(state_accu)
      IDLE_S: begin
        pkt_data_valid      <= 1'b0;
        pkt_data            <= 134'b0;
        head_tag            <= 2'b01;
        cnt_16B             <= 8'b0;
        //* get 8b data;
        if(gmii_data_valid == 1'b1) begin
          for(i=0; i<16; i=i+1) begin
            if(i==cnt_valid)  pkt_tag[i]  <= gmii_data;
            else              pkt_tag[i]  <= pkt_tag[i];
          end
          cnt_valid         <= cnt_valid + 4'd1;
        end
        else begin  //* packet < 16B, discard;
          cnt_valid         <= 4'd0;
        end
        
        //* output/discard 16B data;
        if(cnt_valid == 4'd15) begin
          if(bufferID == 16'hffff) begin
            state_accu      <= OVERFLOW_S;
            `ifdef OPEN_COUNTER
              cnt_discard_gmii2pkt <= cnt_discard_gmii2pkt + 32'd1;
            `endif
          end
          else
            state_accu      <= WAIT_TAIL_S;
        end
      end
      WAIT_TAIL_S: begin
        pkt_data_valid      <= 1'b0;
        if(gmii_data_valid == 1'b1) begin
          //* get 8b data;
          for(i=0; i<16; i=i+1) begin
            if(i==cnt_valid)  pkt_tag[i]  <= gmii_data;
            else              pkt_tag[i]  <= pkt_tag[i];
          end
          cnt_valid         <= cnt_valid + 4'd1;
        
          //* update head tag;
          head_tag          <= 2'b0;
          //* output packet;
          if(cnt_valid == 4'd0) begin
            //* if packet > 2KB, truncate pkt;
            cnt_16B         <= cnt_16B + 8'd1;
            if(cnt_16B == 8'd130) begin
              state_accu      <= OVERFLOW_S;
              pkt_data_valid  <= 1'b1;
              pkt_data        <= {2'b10,4'hf,pkt_tag[0],pkt_tag[1],pkt_tag[2],
                        pkt_tag[3],pkt_tag[4],pkt_tag[5],pkt_tag[6],pkt_tag[7],
                        pkt_tag[8],pkt_tag[9],pkt_tag[10],pkt_tag[11],
                        pkt_tag[12],pkt_tag[13],pkt_tag[14],pkt_tag[15]};
            end
            else begin
              pkt_data_valid  <= 1'b1;
              pkt_data        <= {head_tag,4'hf,pkt_tag[0],pkt_tag[1],pkt_tag[2],
                        pkt_tag[3],pkt_tag[4],pkt_tag[5],pkt_tag[6],pkt_tag[7],
                        pkt_tag[8],pkt_tag[9],pkt_tag[10],pkt_tag[11],
                        pkt_tag[12],pkt_tag[13],pkt_tag[14],pkt_tag[15]};
            end
          end
        end
        else begin  //* output packet;
          pkt_data_valid    <= 1'b1;
          pkt_data          <= {2'b10,cnt_valid-4'd1,pkt_tag[0],pkt_tag[1],pkt_tag[2],
                        pkt_tag[3],pkt_tag[4],pkt_tag[5],pkt_tag[6],pkt_tag[7],
                        pkt_tag[8],pkt_tag[9],pkt_tag[10],pkt_tag[11],
                        pkt_tag[12],pkt_tag[13],pkt_tag[14],pkt_tag[15]};
          state_accu        <= IDLE_S;
          cnt_valid         <= 4'd0;
          //* packet = 16B, discard;
          if(head_tag == 2'b01)
            pkt_data_valid  <= 1'b0;
        end
        
      end
      OVERFLOW_S: begin
        pkt_data_valid      <= 1'b0;
        cnt_valid           <= 4'd0;
        if(gmii_data_valid == 1'b0)
          state_accu        <= IDLE_S;
      end
      default: begin
        state_accu          <= IDLE_S;
      end
    endcase
  end
end


//* delay outputing metadata after 32 clks to guarantee that the 2nd pkt data is received;
reg   [31:0]  temp_valid;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    metadata_valid          <= 1'b0;
    metadata                <= 128'b0;
    temp_valid              <= 32'b0;
    `ifdef OPEN_COUNTER
      cnt_meta_gmii2pkt     <= 32'b0;
    `endif
  end
  else begin
    if(pkt_data_valid == 1'b1 && pkt_data[133:132] == 2'b01) begin
      temp_valid[0]         <= 1'b1;
      //* TO DO...
      metadata              <= {72'b0,(pkt_data[127:80] == 48'h0001_0203_0405),
                                4'b0,pkt_data[74:72],
                              PORT_NUM[7:0],8'b0,
                              pkt_data[87:80],pkt_data[39:32],bufferID};
      `ifdef OPEN_COUNTER
        cnt_meta_gmii2pkt   <= cnt_meta_gmii2pkt + 32'd1;
      `endif
    end
    else begin
      temp_valid[0]         <= 1'b0;
    end
    {metadata_valid,temp_valid[31:1]} <= temp_valid;
  end
end






endmodule
