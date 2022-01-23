/*
 *  picoTSN_hardware -- Hardware for picoTSN.
 *
 *  Copyright (C) 2021-2022 Junnan Li <lijunnan@nudt.edu.cn>.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.20
 *  Description: rule_lookup.
 *	Noted:
 *		1) 128b metadata:
 *			[55:48]		pktType;
 *				[55]	'1' is ptp;
 *				[54:51]	reserved;
 *				[50:48]	ptp type;
 *			[47:40]		inPort;
 *			[39:32]		outPort;
 *			[31:24]		dstMAC[7:0];
 *			[23:16]		srcMAC[7:0];
 *			[15:0]		bufferID;
 */

`timescale 1ns / 1ps

module rule_lookup_1to2(
	input						rst_n,
	input						clk,
	input			[511:0]		metadata_in,
	input			[3:0]		metadata_in_valid,
	input			[3:0]		rden_metadata,
	output	wire	[3:0]		empty_metadata,
	output	wire	[511:0]		data_metadata
	
);
//* metadata_in divided into 4 parts; 
wire	[63:0]	metadata_in_w[3:0];
assign	{metadata_in_w[3],metadata_in_w[2],metadata_in_w[1],
			metadata_in_w[0]} = {metadata_in[447:384],
			metadata_in[319:256],metadata_in[191:128],metadata_in[63:0]};

//* fifo_64b_512 for metadata;
(* mark_debug = "true"*)reg		[3:0]	wren_meta;
(* mark_debug = "true"*)reg		[63:0]	din_meta;
(* mark_debug = "true"*)wire	[63:0]	dout_meta[3:0];
//* 4 dout_meta accumulated to data_metadata;
assign	data_metadata = {64'b0,dout_meta[3],64'b0,dout_meta[2],
							64'b0,dout_meta[1],64'b0,dout_meta[0]};

reg		[3:0]	bitmap_match[3:0];
integer i,j;
//* metadata in;
//*	" metaIn_ready[0] != metaIn_ready[1]" means to process a new meta;
//* 	1) flip metaIn_ready[0] when receiving a new meta;
//*		2) flip metaIn_ready[1] after processing a meta;
//*		3) tag_metaIn_ready != 0, to process the meta;
(* mark_debug = "true"*)reg		[63:0]	temp_meta[3:0];
(* mark_debug = "true"*)reg		[3:0]	metaIn_ready[1:0];
(* mark_debug = "true"*)wire	[3:0]	tag_metaIn_ready;

//* for test;
(* mark_debug = "true"*)reg		[7:0]	cnt_pkt_recv, cnt_pkt_send;

assign	tag_metaIn_ready = metaIn_ready[1]^metaIn_ready[0];

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		din_meta			<= 64'b0;
		for(i=0; i<4; i=i+1) begin
			wren_meta[i]	<= 1'b0;
			temp_meta[i]	<= 64'b0;
			bitmap_match[i]	<= 4'b0;
		end
		metaIn_ready[0]		<= 4'b0;
		metaIn_ready[1]		<= 4'b0;

		cnt_pkt_recv		<= 8'b0;
		cnt_pkt_send		<= 8'b0;
	end
	else begin
		//* lookup dst MAC
		//*		1) set bitmap_match;
		//* 	2) flip metaIn_ready[0];
		for(i=0; i<4; i=i+1) begin
			if(metadata_in_valid[i] == 1'b1) begin
				temp_meta[i]		<= metadata_in_w[i];
				metaIn_ready[0][i]	<= ~metaIn_ready[0][i];
				// for(j=0; j<4; j=j+1) begin
				// 	(*full_case, parallel_case*)
				// 	case(metadata_in_w[i][41:40])
				// 		2'b00: bitmap_match[i]	<= 4'b0010;
				// 		2'b01: bitmap_match[i]	<= 4'b0001;
				// 		2'b10: bitmap_match[i]	<= 4'b1000;
				// 		2'b11: bitmap_match[i]	<= 4'b0100;
				// 	endcase
				// end
				if(metadata_in_w[i][55] == 1'b1) begin
					cnt_pkt_recv		<= 8'd1 + cnt_pkt_recv;
					if(metadata_in_w[i][49:48] == 2'b0)
						bitmap_match[i]	<= 4'b1111;
					else if(metadata_in_w[i][49:48] == 2'd3) //* discard ptp_3
						bitmap_match[i]	<= 4'b0;
					else
						bitmap_match[i]	<= 4'b1 << metadata_in_w[i][41:40];
				end
				else begin
					//* discard not ptp pkt;
					bitmap_match[i]		<= 4'b0;
				end
			end
		end
		
		//* write meta to fifo;
		//*		1) flip metaIn_ready[1];
		wren_meta					<= 4'b0;
		if(tag_metaIn_ready != 4'h0) begin
			(* parallel_case, full_case *)
			casez(tag_metaIn_ready)
				4'b1???: begin
					din_meta			<= temp_meta[3];
					wren_meta			<= bitmap_match[3];
					metaIn_ready[1][3]	<= ~metaIn_ready[1][3];
				end
				4'b01??: begin
					din_meta			<= temp_meta[2];
					wren_meta			<= bitmap_match[2];
					metaIn_ready[1][2]	<= ~metaIn_ready[1][2];
				end
				4'b001?: begin
					din_meta			<= temp_meta[1];
					wren_meta			<= bitmap_match[1];
					metaIn_ready[1][1]	<= ~metaIn_ready[1][1];
				end
				4'b0001: begin
					din_meta			<= temp_meta[0];
					wren_meta			<= bitmap_match[0];
					metaIn_ready[1][0]	<= ~metaIn_ready[1][0];
				end
			endcase
		end
	end
end



genvar i_port;
generate
	for (i_port = 0; i_port < 4; i_port = i_port+1) begin: fifo_inst
		fifo_64b_512 fifo_meta (
			.clk(clk),      				// input wire clk
			.srst(!rst_n),    				// input wire srst
			.din(din_meta),     			// input wire [63 : 0] din
			.wr_en(wren_meta[i_port]), 		// input wire wr_en
			.rd_en(rden_metadata[i_port]), 	// input wire rd_en
			.dout(dout_meta[i_port]),  		// output wire [63 : 0] dout
			.full(),    					// output wire full
			.empty(empty_metadata[i_port]),	// output wire empty
			.data_count() 					// output wire [9 : 0] data_count
		);
	end
endgenerate



endmodule
