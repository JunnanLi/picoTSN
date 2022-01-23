/*
 *  picoTSN_hardware -- Hardware for TSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20 
 *  Description: centralized buffer manager for packets.
 *  Noted:
 *    1) 134b pkt data definition: 
 *      [133:132] head tag, 2'b01 is head, 2'b10 is tail;
 *      [131:128] valid tag, 4'b1111 means sixteen 8b data is valid;
 *      [127:0]   pkt data, invalid part is padded with 0;
 *    2) 16b bufferID
 *      [15:14]   used to distinguish which port;
 *      [13:0]    bufferID, max bufferID: 2^14 for each port;
 *    3) each req_bufferID_en & rden_pkt & ready_pkt is valid in one cycle;
 *    4) if the pkt's head tag isn't 2'b01, means this pkt has been covered;
 *    5) pktData_out is always valid after ready_pkt is '1';
 *    6) packet is buffer in SRAM, which divided into 4 part, similar to 4 fifo;
 */

`timescale 1ns / 1ps
`define RAM_WORDS 16'd4096
`define RAM_DEPTH 12


module buffer_manage_bigFIFO(
  input                 rst_n,
  input                 clk,
  input         [535:0] pktData_in,
  input         [3:0]   pktData_in_valid,
  output  wire  [63:0]  distr_bufferID,
  input         [3:0]   req_bufferID_en,
  input         [63:0]  req_bufferID,
  output  reg   [3:0]   ready_pkt,
  input         [3:0]   rden_pkt,
  output  wire  [535:0] pktData_out
  
  //* connect to DDR;
  // TO DO...
);

//* pktData_in divided into 4 parts; 
wire  [133:0] pktData_in_w[3:0];
assign  {pktData_in_w[3],pktData_in_w[2],pktData_in_w[1],pktData_in_w[0]} = pktData_in;
//* req_bufferID divided into 4 parts;
wire  [15:0]  req_bufferID_w[3:0];
assign  {req_bufferID_w[3],req_bufferID_w[2],req_bufferID_w[1],
              req_bufferID_w[0]} = req_bufferID;

//* 4 distr_bufferID_r accumulated to distr_bufferID;
reg   [15:0]  distr_bufferID_r[3:0];    // 'ffff' means bufferID has been used up;
assign  distr_bufferID = {distr_bufferID_r[3],distr_bufferID_r[2],
              distr_bufferID_r[1],distr_bufferID_r[0]};
//* 4 pktData_out_r accumulated to pktData_out;
(* mark_debug = "true"*)reg   [133:0] pktData_out_r[3:0];
assign  pktData_out = {pktData_out_r[3],pktData_out_r[2],
              pktData_out_r[1],pktData_out_r[0]};

//* blk_134b_4096 for packets;
reg           wren_wrPkt;
reg   [133:0] din_wrPkt;
wire  [133:0] dout_rdPkt;
reg   [`RAM_DEPTH-1:0]  addr_rdPkt,addr_wrPkt;


//* bufferID manager, distribute bufferID;
//* using a RAM to implement 4 FIROs(First In Random Out);
integer i;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    for(i=0; i<4; i=i+1)
      distr_bufferID_r[i]                   <= 16'b0;
    distr_bufferID_r[0][(`RAM_DEPTH-1)-:2]  <= 2'd0;
    distr_bufferID_r[1][(`RAM_DEPTH-1)-:2]  <= 2'd1;
    distr_bufferID_r[2][(`RAM_DEPTH-1)-:2]  <= 2'd2;
    distr_bufferID_r[3][(`RAM_DEPTH-1)-:2]  <= 2'd3;

  end
  else begin
    //* set tag_distr_bufferID when receiving a new packet;
    for(i=0; i<4; i=i+1) begin
      if(pktData_in_valid[i] == 1'b1) begin
        distr_bufferID_r[i][`RAM_DEPTH-3:0] <= distr_bufferID_r[i][`RAM_DEPTH-3:0] + 
          {{(`RAM_DEPTH-3){1'b0}},1'b1};
      end
    end
  end
end


//* write pkt to SRAM;
//* " pktIn_ready[0] != pktIn_ready[1]" means to write packet data
//*   1) flip pktIn_ready[0] when receiving a new packet data;
//*   2) flip pktIn_ready[1] after writing this packet data;
//*   3) tag_pktIn_ready != 0, to write a packet data;
reg   [133:0] temp_pktIn[3:0];
reg   [3:0]   pktIn_ready[1:0];
wire  [3:0]   tag_pktIn_ready;
assign        tag_pktIn_ready = pktIn_ready[1]^pktIn_ready[0];
(* mark_debug = "true"*)reg   [`RAM_DEPTH-1:0]  temp_addrWr[3:0];
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    addr_wrPkt                          <= {`RAM_DEPTH{1'b0}};
    wren_wrPkt                          <= 1'b0;
    din_wrPkt                           <= 134'b0;
    for(i=0; i<4; i=i+1) begin
      temp_addrWr[i]                    <= {`RAM_DEPTH{1'b0}};
      temp_pktIn[i]                     <= 134'b0;
    end
    pktIn_ready[0]                      <= 4'b0;
    pktIn_ready[1]                      <= 4'b0;
  end
  else begin
    for(i=0; i<4; i=i+1) begin
      //* flip pktIn_ready[0] after receiving a new pkt data;
      if(pktData_in_valid[i] == 1'b1) begin
        temp_pktIn[i]                   <= pktData_in_w[i];
        pktIn_ready[0][i]               <= ~pktIn_ready[0][i];
        //* address is updated by distr_bufferID_r;
        temp_addrWr[i]                  <= distr_bufferID_r[i][`RAM_DEPTH-1:0];
      end
    end
    //* write pkt to blk_134b_4096 when tag_pktIn_ready != 4'h0;
    if(tag_pktIn_ready != 4'h0) begin
      wren_wrPkt                        <= 1'b1;
      (* parallel_case, full_case *)
      casez(tag_pktIn_ready)
        4'b1???: begin 
          din_wrPkt                     <= temp_pktIn[3];
          addr_wrPkt                    <= temp_addrWr[3];
          pktIn_ready[1][3]             <= ~pktIn_ready[1][3];
        end
        4'b01??: begin 
          din_wrPkt                     <= temp_pktIn[2];
          addr_wrPkt                    <= temp_addrWr[2];
          pktIn_ready[1][2]             <= ~pktIn_ready[1][2];
        end
        4'b001?: begin 
          din_wrPkt                     <= temp_pktIn[1];
          addr_wrPkt                    <= temp_addrWr[1];
          pktIn_ready[1][1]             <= ~pktIn_ready[1][1];
        end
        4'b0001: begin 
          din_wrPkt                     <= temp_pktIn[0];
          addr_wrPkt                    <= temp_addrWr[0];
          pktIn_ready[1][0]             <= ~pktIn_ready[1][0];
        end
      endcase
    end
    else  wren_wrPkt                    <= 1'b0;
  end
end

//* read pkt from SRAM;
//* "pktOut_ready[0] != pktOut_ready[1]" means to read packet data;
//*   1) flip pktOut_ready[0] when receiving a new packet data;
//*   2) flip pktOut_ready[1] after writing this packet data;
//*   3) tag_pktOut_ready != 0, to write a packet data;
(* mark_debug = "true"*)reg   [`RAM_DEPTH-1:0]  temp_addrRd[3:0];
reg   [3:0] pktOut_ready[1:0];
wire  [3:0] tag_pktOut_ready;
assign  tag_pktOut_ready = pktOut_ready[1]^pktOut_ready[0];
//* bitmap, who gets the choice of reading sram, stage 0 to stage 2;
reg   [3:0] tag_alreadyRd[2:0];
    
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    addr_rdPkt                          <= {`RAM_DEPTH{1'b0}};
    for(i=0; i<4; i=i+1) begin
      pktData_out_r[i]                  <= 134'b0;
      ready_pkt[i]                      <= 1'b0;
      temp_addrRd[i]                    <= {`RAM_DEPTH{1'b0}};
    end
    pktOut_ready[0]                     <= 4'b0;
    pktOut_ready[1]                     <= 4'b0;
    tag_alreadyRd[0]                    <= 4'b0;
    tag_alreadyRd[1]                    <= 4'b0;
    tag_alreadyRd[2]                    <= 4'b0;
  end
  else begin
    //* flip pktOut_ready[0] after requesting to read one pkt data;
    for(i=0; i<4; i=i+1) begin
      //* prepare to read a new pkt when receiving a new req_bufferID_en;
      //*   1) flip pktOut_ready[0];
      //*   2) initial start address;
      if(req_bufferID_en[i] == 1'b1) begin
        temp_addrRd[i]                  <= req_bufferID_w[i][`RAM_DEPTH-1:0];
        pktOut_ready[0][i]              <= ~pktOut_ready[0][i];
      end
      else if(rden_pkt[i] == 1'b1) begin
        temp_addrRd[i][`RAM_DEPTH-3:0]  <= temp_addrRd[i][`RAM_DEPTH-3:0] + 
                                            {{(`RAM_DEPTH-3){1'b0}},1'b1};
        pktOut_ready[0][i]              <= ~pktOut_ready[0][i];
      end
    end
    
    //* read a pkt data when tag_pktOut_ready != 0;
    //*   1) flip pktOut_ready[1];
    //*   2) set tag_alreadyRd[0] (bitmap, who gets the choice of reading sram);
    tag_alreadyRd[0]                  <= 4'b0;
    if(tag_pktOut_ready != 4'h0) begin
      (* parallel_case, full_case *)
      casez(tag_pktOut_ready)
        4'b1???: begin
          addr_rdPkt                  <= temp_addrRd[3];
          pktOut_ready[1][3]          <= ~pktOut_ready[1][3];
          tag_alreadyRd[0]            <= 4'd8;
        end
        4'b01??: begin
          addr_rdPkt                  <= temp_addrRd[2];
          pktOut_ready[1][2]          <= ~pktOut_ready[1][2];
          tag_alreadyRd[0]            <= 4'd4;
        end
        4'b001?: begin
          addr_rdPkt                  <= temp_addrRd[1];
          pktOut_ready[1][1]          <= ~pktOut_ready[1][1];
          tag_alreadyRd[0]            <= 4'd2;
        end
        4'b0001: begin
          addr_rdPkt                  <= temp_addrRd[0];
          pktOut_ready[1][0]          <= ~pktOut_ready[1][0];
          tag_alreadyRd[0]            <= 4'd1;
        end
      endcase
    end
    
    //* get data from blk_134b_4096, and set ready_pkt;
    for(i=0; i<4; i=i+1) begin
      if(tag_alreadyRd[2][i] == 1'b1) begin
        pktData_out_r[i]              <= dout_rdPkt;
        //* assign ready_pkt when reading pkt head;
        ready_pkt[i]                  <= 1'b1;
      end
      else begin
        pktData_out_r[i]              <= pktData_out_r[i];
        ready_pkt[i]                  <= 1'b0;
      end
    end
    
    //* record tag_alreadyRd;
    {tag_alreadyRd[2],tag_alreadyRd[1]} <= {tag_alreadyRd[1],tag_alreadyRd[0]};
  end
end

blk_134b_4096 pkt_ram (
  .clka(clk),         // input wire clka
  .wea(wren_wrPkt),   // input wire [0 : 0] wea
  .addra(addr_wrPkt), // input wire [11 : 0] addra
  .dina(din_wrPkt),   // input wire [133 : 0] dina
  .douta(),           // output wire [133 : 0] douta
  .clkb(clk),         // input wire clkb
  .web(1'b0),         // input wire [0 : 0] web
  .addrb(addr_rdPkt), // input wire [11 : 0] addrb
  .dinb(134'b0),      // input wire [133 : 0] dinb
  .doutb(dout_rdPkt)  // output wire [133 : 0] doutb
);


//* cnt_pkt for test;
(* mark_debug = "true"*)reg   tag_almost_full;
(* mark_debug = "true"*)reg   tag_full;
(* mark_debug = "true"*)reg   [10:0] usedw_pktBuf;
reg temp_gmii_valid;
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    tag_almost_full         <= 1'b0;
    tag_full                <= 1'b0;
    usedw_pktBuf            <= 11'b0;
  end
  else begin
    tag_full                <= 1'b0;
    if(temp_addrWr[0][9:0] == (temp_addrRd[0][9:0] - 10'd1))
      tag_full              <= 1'b1;

    tag_almost_full         <= 1'b0;
    if(temp_addrWr[0][9:0] == (temp_addrRd[0][9:0] - 10'd8))
      tag_almost_full       <= 1'b1;
    if(temp_addrWr[0][9:0] >= temp_addrRd[0][9:0])
      usedw_pktBuf          <= {1'b0,temp_addrWr[0][9:0]-temp_addrRd[0][9:0]};
    else
      usedw_pktBuf          <= {1'b1,temp_addrWr[0][9:0]}-{1'b0,temp_addrRd[0][9:0]};
  end
end


endmodule
