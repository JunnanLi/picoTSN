/*
 *  picoTSN_hardware -- Hardware for picoTSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20 
 *  Description: Top Module of picoTSN_hardware.
 *  Noted:
 *    1) rgmii2gmii & gmii_rx2rgmii are processed by language templates;
 *    2) rgmii_rx is constrained by set_input_delay "-2.0 ~ -0.7";
 *    3) 134b pkt data definition: 
 *      [133:132] head tag, 2'b01 is head, 2'b10 is tail;
 *      [131:128] valid tag, 4'b1111 means sixteen 8b data is valid;
 *      [127:0]   pkt data, invalid part is padded with 0;
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

`define NUM_PORT 4
 
module test_eth_top(
  //* system input, clk;
  input               sys_clk,
  input               rst_n,
  //* rgmii port;
  output  wire        mdio_mdc_0,
  inout               mdio_mdio_io_0,
  output  wire        phy_reset_n_0,
  input         [3:0] rgmii_rd_0,
  input               rgmii_rx_ctl_0,
  input               rgmii_rxc_0,
  output  wire  [3:0] rgmii_td_0,
  output  wire        rgmii_tx_ctl_0,
  output  wire        rgmii_txc_0,
  
  output  wire        mdio_mdc_1,
  inout               mdio_mdio_io_1,
  output  wire        phy_reset_n_1,
  input         [3:0] rgmii_rd_1,
  input               rgmii_rx_ctl_1,
  input               rgmii_rxc_1,
  output  wire  [3:0] rgmii_td_1,
  output  wire        rgmii_tx_ctl_1,
  output  wire        rgmii_txc_1,
  
  output  wire        mdio_mdc_2,
  inout               mdio_mdio_io_2,
  output  wire        phy_reset_n_2,
  input         [3:0] rgmii_rd_2,
  input               rgmii_rx_ctl_2,
  input               rgmii_rxc_2,
  output  wire  [3:0] rgmii_td_2,
  output  wire        rgmii_tx_ctl_2,
  output  wire        rgmii_txc_2,

  output  wire        mdio_mdc_3,
  inout               mdio_mdio_io_3,
  output  wire        phy_reset_n_3,
  input         [3:0] rgmii_rd_3,
  input               rgmii_rx_ctl_3,
  input               rgmii_rxc_3,
  output  wire  [3:0] rgmii_td_3,
  output  wire        rgmii_tx_ctl_3,
  output  wire        rgmii_txc_3

  ,input              time_int_i
  ,output wire        gnd_test
  ,output wire        time_int_o

  //*lcd
  ,output  wire        lcd_dclk   // lcd clock;
  ,output  wire        lcd_hs     // lcd horizontal synchronization;
  ,output  wire        lcd_vs     // lcd vertical synchronization;  
  ,output  wire        lcd_de     // lcd data valid;
  ,output  wire  [7:0] lcd_r      // lcd red;
  ,output  wire  [7:0] lcd_g      // lcd green;
  ,output  wire  [7:0] lcd_b      // lcd blue;
);

assign gnd_test = 1'b0;

//* clock & locker;
wire  clk_125m, clk_9m;
wire  locked;   // locked =1 means generating 125M clock successfully;
wire  [15:0]  local_time;
wire  [3:0]   update_time_valid;
wire  [63:0]  update_time[3:0];
// wire  [39:0]  global_time;

//* connected wire;
//* Data Flow: gmii_rx - > asfifo_recv -> checkCRC -> gmii2pkt -> UM -> 
//*   pkt2gmii -> calCRC -> gmii_tx;
//* checkCRC & modifyPKT & calCRC;
(* mark_debug = "true"*)wire  [3:0] gmiiEr_checkCRC, gmiiEr_calCRC, gmiiEr_modifyPKT;
(* mark_debug = "true"*)wire  [7:0] gmiiTxd_checkCRC[3:0], gmiiTxd_calCRC[3:0], gmiiTxd_modifyPKT[3:0];
(* mark_debug = "true"*)wire  [3:0] gmiiEn_checkCRC, gmiiEn_calCRC, gmiiEn_modifyPKT;

//* gmii2pkt -> UM -> pkt2gmii -> calCRC;
wire  [133:0] pktData_gmii[3:0];
(* mark_debug = "true"*)wire  [3:0]   pktData_valid_gmii;
wire  [7:0]   gmii_txd_pkt[3:0];
wire  [3:0]   gmii_tx_en_pkt;

//* gmii_rx (gmii_rx - > asfifo_recv);
wire  [3:0]   gmiiRclk_rgmii; 
(* mark_debug = "true"*)wire  [7:0]   gmiiRxd_rgmii[3:0];
(* mark_debug = "true"*)wire  [3:0]   gmiiEn_rgmii;
(* mark_debug = "true"*)wire  [3:0]   gmiiEr_rgmii;

//* asfifo_recv -> checkCRC;
(* mark_debug = "true"*)wire  [7:0]   gmiiRxd_asfifo[3:0];
(* mark_debug = "true"*)wire  [3:0]   gmiiEn_asfifo;
wire          gmiiEr_asfifo[3:0];

//* TODO...
wire  [3:0]   sendPkt_valid_modifyPkt;    //* ?
wire  [3:0]   recvPktType_asfifo[3:0];    //* pkt type;
wire  [3:0]   sendPktType_modifyPkt[3:0]; //* ?

//* metadata;
wire  [127:0] metadata_gmii[3:0];         //* generated by gmii_to_134b_pkt;
(* mark_debug = "true"*)wire  [3:0]   metadata_valid_gmii;
(* mark_debug = "true"*)wire  [15:0]  bufferID_pkt2gmii[3:0];
//* for test;
// (* mark_debug = "true"*)wire  [63:0]  metadata_gmii_64b[3:0];
// assign  metadata_gmii_64b[0] = metadata_gmii[0][63:0];
// assign  metadata_gmii_64b[1] = metadata_gmii[1][63:0];
// assign  metadata_gmii_64b[2] = metadata_gmii[2][63:0];
// assign  metadata_gmii_64b[3] = metadata_gmii[3][63:0];

//* buffer manager
(* mark_debug = "true"*)wire  [15:0]  bufferID_distr[3:0];  //* next bufferID;
(* mark_debug = "true"*)wire  [3:0]   readyPkt_pkt2gmii;    //* ready to read pkt from buffer;
(* mark_debug = "true"*)wire  [3:0]   rdenPkt_pkt2gmii;     //* read pkt from buffer;
(* mark_debug = "true"*)wire  [133:0] dataPkt_pkt2gmii[3:0];//* pkt;
(* mark_debug = "true"*)wire  [3:0]   rdenBufferID_pkt2gmii;//* pkt's bufferID (waited to read);

//* rule lookup
(* mark_debug = "true"*)wire  [3:0]   emptyMeta_lookup;     //* empty signal of meta;
(* mark_debug = "true"*)wire  [3:0]   rdenMeta_lookup;      //* read meta;
wire  [127:0] dataMeta_lookup[3:0]; //* meta;

//* connected wire
//* TODO..., include speed_mode, clock_speed, mdio (gmii_to_rgmii IP);
// wire  [1:0]   speed_mode[3:0], clock_speed[3:0];
// wire          mdio_gem_mdc, mdio_gem_o, mdio_gem_t;
// wire          mdio_gem_i[3:0];

//* pin to rgmii;
  wire  [3:0] rgmii_rd_w[3:0], rgmii_td_w[3:0];
  wire        rgmii_rx_ctl_w[3:0], rgmii_tx_ctl_w[3:0];
  wire        rgmii_rxc_w[3:0], rgmii_txc_w[3:0];

  assign rgmii_rd_w[0] = rgmii_rd_0;
  assign rgmii_rd_w[1] = rgmii_rd_1;
  assign rgmii_rd_w[2] = rgmii_rd_2;
  assign rgmii_rd_w[3] = rgmii_rd_3;
  assign rgmii_rx_ctl_w[0] = rgmii_rx_ctl_0;
  assign rgmii_rx_ctl_w[1] = rgmii_rx_ctl_1;
  assign rgmii_rx_ctl_w[2] = rgmii_rx_ctl_2;
  assign rgmii_rx_ctl_w[3] = rgmii_rx_ctl_3;
  assign rgmii_rxc_w[0] = rgmii_rxc_0;
  assign rgmii_rxc_w[1] = rgmii_rxc_1;
  assign rgmii_rxc_w[2] = rgmii_rxc_2;
  assign rgmii_rxc_w[3] = rgmii_rxc_3;

  assign rgmii_td_0 = rgmii_td_w[0];
  assign rgmii_td_1 = rgmii_td_w[1];
  assign rgmii_td_2 = rgmii_td_w[2];
  assign rgmii_td_3 = rgmii_td_w[3];
  assign rgmii_tx_ctl_0 = rgmii_tx_ctl_w[0];
  assign rgmii_tx_ctl_1 = rgmii_tx_ctl_w[1];
  assign rgmii_tx_ctl_2 = rgmii_tx_ctl_w[2];
  assign rgmii_tx_ctl_3 = rgmii_tx_ctl_w[3];
  assign rgmii_txc_0 = rgmii_txc_w[0];
  assign rgmii_txc_1 = rgmii_txc_w[1];
  assign rgmii_txc_2 = rgmii_txc_w[2];
  assign rgmii_txc_3 = rgmii_txc_w[3];

  //* assign phy_reset_n = 1, haven't been used;
  assign phy_reset_n_0 = rst_n;
  assign phy_reset_n_1 = rst_n;
  assign phy_reset_n_2 = rst_n;
  assign phy_reset_n_3 = rst_n;

  //* assign mdio_mdc = 0, haven't been used;
  assign mdio_mdc_0 = 1'b0;
  assign mdio_mdc_1 = 1'b0;
  assign mdio_mdc_2 = 1'b0;
  assign mdio_mdc_3 = 1'b0;

//* cnt, haven't been used;
(* mark_debug = "true"*)wire  [31:0]  cntPkt_asynRecvPkt[3:0], cntPkt_gmii2pkt, cntPkt_pkt2gmii[3:0];

//* system reset signal, low is active;
wire sys_rst_n;
assign sys_rst_n = rst_n & locked;



  //* gen 125M clock;
  clk_wiz_0 clk_to_125m(
    // Clock out ports
    .clk_out1(clk_125m),        // output 125m
    .clk_out2(clk_9m),          // output 9m;
    // Status and control signals
    .reset(!rst_n),             // input reset
    .locked(locked),            // output locked
    // Clock in ports
    .clk_in1(sys_clk)
    // .clk_in1_p(sys_clk_p),   // input clk_in1_p
    // .clk_in1_n(sys_clk_n)    // input clk_in1_n
  );
  
  //*************** sub-modules ***************//   
  genvar i_rgmii;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: rgmii2gmii_inst
      //* format transform between gmii with rgmii;
      util_gmii_to_rgmii rgmii2gmii(
        .rst_n(sys_rst_n),
        .rgmii_rd(rgmii_rd_w[i_rgmii]),         // input---|
        .rgmii_rx_ctl(rgmii_rx_ctl_w[i_rgmii]), // input   |--+
        .rgmii_rxc(rgmii_rxc_w[i_rgmii]),       // input---|  |
                                                //         |
        .gmii_rx_clk(gmiiRclk_rgmii[i_rgmii]),  // output--|  |
        .gmii_rxd(gmiiRxd_rgmii[i_rgmii]),      // output  |<-+
        .gmii_rx_dv(gmiiEn_rgmii[i_rgmii]),     // output  |
        .gmii_rx_er(gmiiEr_rgmii[i_rgmii]),     // output--|
        
        .rgmii_txc(rgmii_txc_w[i_rgmii]),       // output--|
        .rgmii_td(rgmii_td_w[i_rgmii]),         // output  |<-+
        .rgmii_tx_ctl(rgmii_tx_ctl_w[i_rgmii]), // output--|  |
                                                //            |
        .gmii_tx_clk(clk_125m),                 // input---|  |
        .gmii_txd(gmiiTxd_calCRC[i_rgmii]),     // input   |--+
        .gmii_tx_en(gmiiEn_calCRC[i_rgmii]),    // input   |
        .gmii_tx_er(1'b0)                       // input---|
      );
    end
  endgenerate

  //* asynchronous recving packets:
  //*   1) discard frame's head tag;  
  //*   2) record recv time;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: asynRecvPkt_inst
      asyn_recv_packet asyn_recv_packet_inst (
        .rst_n(sys_rst_n),
        .gmii_rx_clk(gmiiRclk_rgmii[i_rgmii]),
        .gmii_rxd(gmiiRxd_rgmii[i_rgmii]),
        .gmii_rx_dv(gmiiEn_rgmii[i_rgmii]),
        .gmii_rx_er(gmiiEr_rgmii[i_rgmii]),
        .clk_125m(clk_125m),
        .gmii_txd(gmiiRxd_asfifo[i_rgmii]),
        .gmii_tx_en(gmiiEn_asfifo[i_rgmii]),
        .gmii_tx_er(gmiiEr_asfifo[i_rgmii]),
        .local_time(local_time[15:0]),
        .update_time_valid(update_time_valid[i_rgmii]),
        .update_time(update_time[i_rgmii]),
        .cnt_pkt(cntPkt_asynRecvPkt[i_rgmii])
      );
    end
  endgenerate
  
  //* check CRC of received packets:
  //*   1) discard CRC;
  //*   2) check CRC, TO DO...;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: checkCRC_inst
      
      gmii_crc_check checkCRC(
        .rst_n(sys_rst_n),
        .clk(clk_125m),
        .gmii_dv_i(gmiiEn_asfifo[i_rgmii]),
        .gmii_er_i(gmiiEr_asfifo[i_rgmii]),
        .gmii_data_i(gmiiRxd_asfifo[i_rgmii]),
        
        .gmii_en_o(gmiiEn_checkCRC[i_rgmii]),
        .gmii_er_o(gmiiEr_checkCRC[i_rgmii]),
        .gmii_data_o(gmiiTxd_checkCRC[i_rgmii])
      );
    end
  endgenerate
  
  //* gen 134b data;
  //*   1) accumulate sixteen 8b-data to one 128b data;
  //*   2) gen 128b (64b is used) metadata;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: gmii2pkt_inst
      gmii_to_134b_pkt #(
        .PORT_NUM(i_rgmii)
      )gmii2pkt(
        .rst_n(rst_n),
        .clk(clk_125m),
        .gmii_data(gmiiTxd_checkCRC[i_rgmii]),
        .gmii_data_valid(gmiiEn_checkCRC[i_rgmii]),
        .pkt_data(pktData_gmii[i_rgmii]),
        .pkt_data_valid(pktData_valid_gmii[i_rgmii]),
        .metadata(metadata_gmii[i_rgmii]),
        .metadata_valid(metadata_valid_gmii[i_rgmii]),
        .bufferID(bufferID_distr[i_rgmii])
      );
    end
  endgenerate
  
  
  buffer_manage_bigFIFO bufferManage(
    .rst_n(sys_rst_n),
    .clk(clk_125m),
    .pktData_in({pktData_gmii[3],pktData_gmii[2],
            pktData_gmii[1],pktData_gmii[0]}),
    .pktData_in_valid({pktData_valid_gmii[3],pktData_valid_gmii[2],
            pktData_valid_gmii[1],pktData_valid_gmii[0]}),
    .distr_bufferID({bufferID_distr[3],bufferID_distr[2],
            bufferID_distr[1],bufferID_distr[0]}),
    .req_bufferID_en({rdenBufferID_pkt2gmii[3],rdenBufferID_pkt2gmii[2],
            rdenBufferID_pkt2gmii[1],rdenBufferID_pkt2gmii[0]}),
    .req_bufferID({bufferID_pkt2gmii[3],bufferID_pkt2gmii[2],
            bufferID_pkt2gmii[1],bufferID_pkt2gmii[0]}),
    .ready_pkt({readyPkt_pkt2gmii[3],readyPkt_pkt2gmii[2],
            readyPkt_pkt2gmii[1],readyPkt_pkt2gmii[0]}),
    .rden_pkt({rdenPkt_pkt2gmii[3],rdenPkt_pkt2gmii[2],
            rdenPkt_pkt2gmii[1],rdenPkt_pkt2gmii[0]}),
    .pktData_out({dataPkt_pkt2gmii[3],dataPkt_pkt2gmii[2],
            dataPkt_pkt2gmii[1],dataPkt_pkt2gmii[0]})
  );
  
  rule_lookup_1to2 lookup(
    .rst_n(sys_rst_n),
    .clk(clk_125m),
    //* metadata in;
    .metadata_in({metadata_gmii[3],metadata_gmii[2],
            metadata_gmii[1],metadata_gmii[0]}),
    .metadata_in_valid({metadata_valid_gmii[3],metadata_valid_gmii[2],
            metadata_valid_gmii[1],metadata_valid_gmii[0]}),
    //* metadata out;
    .empty_metadata({emptyMeta_lookup[3],emptyMeta_lookup[2],
            emptyMeta_lookup[1],emptyMeta_lookup[0]}),
    .rden_metadata({rdenMeta_lookup[3],rdenMeta_lookup[2],
            rdenMeta_lookup[1],rdenMeta_lookup[0]}),
    .data_metadata({dataMeta_lookup[3],dataMeta_lookup[2],
            dataMeta_lookup[1],dataMeta_lookup[0]})
  );
  
  generate
    for (i_rgmii = 0; i_rgmii < 4; i_rgmii = i_rgmii+1) begin: pkt2gmii_inst
      pkt_134b_to_gmii pkt2gmii(
        .rst_n(rst_n),
        .clk(clk_125m),
        .empty_metadata(emptyMeta_lookup[i_rgmii]),
        .rden_metadata(rdenMeta_lookup[i_rgmii]),
        .data_metadata(dataMeta_lookup[i_rgmii][15:0]),
        .req_bufferID_en(rdenBufferID_pkt2gmii[i_rgmii]),
        .req_bufferID(bufferID_pkt2gmii[i_rgmii]),
        .ready_pkt(readyPkt_pkt2gmii[i_rgmii]),
        .rden_pkt(rdenPkt_pkt2gmii[i_rgmii]),
        .data_pkt(dataPkt_pkt2gmii[i_rgmii]),
        .gmii_data(gmii_txd_pkt[i_rgmii]),
        .gmii_data_valid(gmii_tx_en_pkt[i_rgmii]),
        .cnt_pkt()
      );
    end
  endgenerate
  
  //* add output time for PTP packets;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: modifyPkt_inst
      // assign gmiiEn_modifyPKT[i_rgmii] = gmii_tx_en_pkt[i_rgmii];
      // assign gmiiEr_modifyPKT[i_rgmii] = 1'b0;
      // assign gmiiTxd_modifyPKT[i_rgmii] = gmii_txd_pkt[i_rgmii];
      
      modify_packet modifyPkt(
        .rst_n(sys_rst_n),
        .clk(clk_125m),
        .gmii_dv_i(gmii_tx_en_pkt[i_rgmii]),
        .gmii_er_i(1'b0),
        .gmii_data_i(gmii_txd_pkt[i_rgmii]),
        
        .gmii_en_o(gmiiEn_modifyPKT[i_rgmii]),
        .gmii_er_o(gmiiEr_modifyPKT[i_rgmii]),
        .gmii_data_o(gmiiTxd_modifyPKT[i_rgmii]),
        .local_time(local_time),
        .cnt_pkt()
      );
    end
  endgenerate
  
  //* calculate CRC of received packets;
  generate
    for (i_rgmii = 0; i_rgmii < `NUM_PORT; i_rgmii = i_rgmii+1) begin: calCRC_inst
      
      gmii_crc_calculate calCRC(
        .rst_n(sys_rst_n),
        .clk(clk_125m),
        .gmii_dv_i(gmiiEn_modifyPKT[i_rgmii]),
        .gmii_er_i(gmiiEr_modifyPKT[i_rgmii]),
        .gmii_data_i(gmiiTxd_modifyPKT[i_rgmii]),
        
        .gmii_en_o(gmiiEn_calCRC[i_rgmii]),
        .gmii_er_o(gmiiEr_calCRC[i_rgmii]),
        .gmii_data_o(gmiiTxd_calCRC[i_rgmii])
      );
    end
  endgenerate
  
  //* connect local_timer with lcd;
  (* mark_debug = "true"*)wire  [11:0]  offset_time;
  (* mark_debug = "true"*)wire          offset_time_valid;

  local_timer localTimer(
    .rst_n(rst_n),
    .clk(clk_125m),
    .local_time(local_time),
    .update_time_valid({update_time_valid[3],update_time_valid[2],
                        update_time_valid[1],update_time_valid[0]}),
    .update_time({update_time[3],update_time[2],update_time[1],update_time[0]}),
    .time_int_i(time_int_i),
    .time_int_o(time_int_o),

    //* connected to lcd;
    .offset_time_o(offset_time),
    .offset_time_valid_o(offset_time_valid)
  );

  assign lcd_dclk = ~clk_9m;
  lcd lcd_inst(
    .core_clk         (clk_125m         ),
    .core_dis_data    (offset_time      ),
    .core_dis_data_wr (offset_time_valid),
    .sys_clk          (~clk_9m          ),
    .rst              (~rst_n           ),
    .hs               (lcd_hs           ),
    .vs               (lcd_vs           ),
    .de               (lcd_de           ),
    .rgb_r            (lcd_r            ),
    .rgb_g            (lcd_g            ),
    .rgb_b            (lcd_b            )
  );


endmodule
