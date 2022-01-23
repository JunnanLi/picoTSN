/*
 *  vga_hardware -- Hardware for vga.
 *
 *  Please communicate with Junnan Li <lijunnan@nudt.edu.cn> when meeting any question.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Data: 2021.11.25
 *  Description: teris_array. 
 */


module lcd_array(
  input             clk,      // pixel clock;
  input             rst,      // reset signal high active;
  input     [11:0]  h_cnt,    // current count (point) of horizontal line;
  input     [11:0]  v_cnt,    // current count (point) of vertical line;
  input     [11:0]  active_x, // current active count (point) of horizontal line;     
  input     [11:0]  active_y, // current active count (point) of vertical line;
  input     [15:0]  distance, // four bytes;
  input             distance_valid,
  output  reg       temp_bit
);

  reg   [27:0]      array_bitmap[14:0], temp_bitmap;
  reg   [14:0]      array_bitmap_cloumn[20:0];
  wire  [14:0]      array_bitmap_cloumn_w[19:0];

  integer i;
  always @(posedge clk or posedge rst) begin
    if (rst == 1'b1) begin
      // reset
      temp_bit                    <= 1'b0;
      for(i=0; i<15; i=i+1)
        array_bitmap[i]           <= 28'b0;
      temp_bitmap                 <= 28'b0;
      for(i=0; i<20; i=i+1)
        array_bitmap_cloumn[i]    <= 15'b0;
      // array_bitmap_cloumn[20]     <= {8'b0,2'b1,5'b0}; //* dot;
    end
    else begin
      if((h_cnt == 0) && (v_cnt == 0)) begin
        for(i=0; i<15; i=i+1) begin
          array_bitmap[i]         <= {2'b0,array_bitmap_cloumn[19][i],array_bitmap_cloumn[18][i],array_bitmap_cloumn[17][i],
                                            array_bitmap_cloumn[16][i],array_bitmap_cloumn[15][i],
                                      1'b0,array_bitmap_cloumn[14][i],array_bitmap_cloumn[13][i],array_bitmap_cloumn[12][i],
                                            array_bitmap_cloumn[11][i],array_bitmap_cloumn[10][i],
                                      1'b0,array_bitmap_cloumn[9][i],array_bitmap_cloumn[8][i],array_bitmap_cloumn[7][i],
                                            array_bitmap_cloumn[6][i],array_bitmap_cloumn[5][i],
                                      // 1'b0,1'b0,array_bitmap_cloumn[20][i],
                                      1'b0,array_bitmap_cloumn[4][i],array_bitmap_cloumn[3][i],array_bitmap_cloumn[2][i],
                                            array_bitmap_cloumn[1][i],array_bitmap_cloumn[0][i],3'b0};
        end
      end
      //* update array_bitmap_cloumn;
      if(distance_valid == 1'b1)
        for(i=0; i<20; i=i+1)
          array_bitmap_cloumn[i]  <= array_bitmap_cloumn_w[i];

      //* shift temp_bitmap
      if(h_cnt == 0) begin
        //* update temp_bitmap;
        case(active_y[7:4])
          4'd0: temp_bitmap   <= array_bitmap[0];
          4'd1: temp_bitmap   <= array_bitmap[1];
          4'd2: temp_bitmap   <= array_bitmap[2];
          4'd3: temp_bitmap   <= array_bitmap[3];
          4'd4: temp_bitmap   <= array_bitmap[4];
          4'd5: temp_bitmap   <= array_bitmap[5];
          4'd6: temp_bitmap   <= array_bitmap[6];
          4'd7: temp_bitmap   <= array_bitmap[7];
          4'd8: temp_bitmap   <= array_bitmap[8];
          4'd9: temp_bitmap   <= array_bitmap[9];
          4'd10: temp_bitmap  <= array_bitmap[10];
          4'd11: temp_bitmap  <= array_bitmap[11];
          4'd12: temp_bitmap  <= array_bitmap[12];
          4'd13: temp_bitmap  <= array_bitmap[13];
          4'd14: temp_bitmap  <= array_bitmap[14];
          default:temp_bitmap <= array_bitmap[0];
        endcase
      end
      else if(active_x[3:0] == 4'd15) begin
        temp_bitmap         <= {temp_bitmap[26:0],1'b0};
        temp_bit            <= temp_bitmap[27];
      end
    end
  end

  genvar i_num;
  generate 
    for(i_num=0; i_num<4; i_num=i_num+1) begin: get_num
      get_num genNum_inst(
        .num(distance[15-i_num*4:12-i_num*4]),
        .array_bitmap_cloumn_0(array_bitmap_cloumn_w[0+i_num*5]),
        .array_bitmap_cloumn_1(array_bitmap_cloumn_w[1+i_num*5]),
        .array_bitmap_cloumn_2(array_bitmap_cloumn_w[2+i_num*5]),
        .array_bitmap_cloumn_3(array_bitmap_cloumn_w[3+i_num*5]),
        .array_bitmap_cloumn_4(array_bitmap_cloumn_w[4+i_num*5])
      );
    end
  endgenerate

endmodule

module get_num(
  input         [3:0]   num,
  output  reg   [14:0]  array_bitmap_cloumn_0,
  output  reg   [14:0]  array_bitmap_cloumn_1,
  output  reg   [14:0]  array_bitmap_cloumn_2,
  output  reg   [14:0]  array_bitmap_cloumn_3,
  output  reg   [14:0]  array_bitmap_cloumn_4
);

  always @(num) begin
    (* parallel_case *)
    case(num)
      4'd0: begin
        array_bitmap_cloumn_0  = {4'b0,5'b11111,6'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,1'b0,1'b1,3'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,3'b0,1'b1,1'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {4'b0,5'b11111,6'b0};
      end
      4'd1: begin
        array_bitmap_cloumn_0  = 15'b0;
        array_bitmap_cloumn_1  = {3'b0,1'b0,1'b1,4'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,7'b1111111,5'b0};
        array_bitmap_cloumn_3  = {3'b0,6'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = 15'b0;
      end
      4'd2: begin
        array_bitmap_cloumn_0  = {3'b0,1'b0,1'b1,4'b0,1'b1,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,4'b0,2'b11,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,3'b0,1'b1,1'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b0,2'b11,3'b0,1'b1,5'b0};
      end
      4'd3: begin
        array_bitmap_cloumn_0  = {3'b0,1'b0,1'b1,3'b0,1'b1,1'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,5'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b0,2'b11,1'b0,2'b11,1'b0,5'b0};
      end
      4'd4: begin
        array_bitmap_cloumn_0  = {3'b0,3'b0,2'b11,2'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,2'b0,1'b1,1'b0,1'b1,2'b0,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b0,1'b1,2'b0,1'b1,2'b0,5'b0};
        array_bitmap_cloumn_3  = {3'b0,7'b1111111,5'b0};
        array_bitmap_cloumn_4  = {3'b0,4'b0,1'b1,2'b0,5'b0};
      end
      4'd5: begin
        array_bitmap_cloumn_0  = {3'b0,3'b111,2'b0,1'b1,1'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,1'b0,1'b1,3'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,1'b0,1'b1,3'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,1'b0,1'b1,3'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b1,2'b0,3'b111,1'b0,5'b0};
      end
      4'd6: begin
        array_bitmap_cloumn_0  = {3'b0,1'b0,5'b11111,1'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b0,1'b1,2'b0,2'b11,1'b0,5'b0};
      end
      4'd7: begin
        array_bitmap_cloumn_0  = {3'b0,1'b1,6'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,3'b0,3'b0,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,4'b1111,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,1'b0,1'b1,4'b0,5'b0};
        array_bitmap_cloumn_4  = {3'b0,2'b11,5'b0,5'b0};
      end
      4'd8: begin
        array_bitmap_cloumn_0  = {3'b0,1'b0,2'b11,1'b0,2'b11,1'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b0,2'b11,1'b0,2'b11,1'b0,5'b0};
      end
      4'd9: begin
        array_bitmap_cloumn_0  = {3'b0,1'b0,2'b11,2'b0,1'b1,1'b0,5'b0};
        array_bitmap_cloumn_1  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_2  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_3  = {3'b0,1'b1,2'b0,1'b1,2'b0,1'b1,5'b0};
        array_bitmap_cloumn_4  = {3'b0,1'b0,5'b11111,1'b0,5'b0};
      end
      default: begin
      end
    endcase
  end

endmodule