/*
 *  vga_hardware -- Hardware for vga.
 *
 *  Please communicate with Junnan Li <lijunnan@nudt.edu.cn> when meeting any question.
 *  Copyright and related rights are licensed under the MIT license.
 *
 *  Last updated date: 2022.01.19
 *  Description: binary to bcd. 
 */


module binary_to_bcd(
    input               clk,
    input               rst,
    input               bin_in_valid,
    input       [11:0]  bin_in,
    output  wire[15:0]  bcd_out,
    output  reg         bcd_out_valid,
    output  wire        ready
    );
    
    //State variables
    localparam  IDLE_S  = 2'd0,
                ADD_S   = 2'd1,
                SHIFT_S = 2'd2;
    
    reg [1:0]   state_bcd;
    reg [27:0]  bcd_data;
    reg [3:0]   sh_counter;
    reg [1:0]   add_counter;
    
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            bcd_out_valid           <= 1'b0;
            add_counter             <= 2'b0;
            bcd_data                <= 28'b0;
            state_bcd               <= IDLE_S;
        end
        else begin 
          case(state_bcd)
            IDLE_S: begin
                bcd_out_valid       <= 1'b0;
                if(bin_in_valid == 1'b1) begin
                    add_counter     <= 2'b0;
                    sh_counter      <= 4'b0;
                    bcd_data        <= 28'b0;
                    bcd_data        <= {16'b0, bin_in};
                    state_bcd       <= ADD_S;
                end
            end
            ADD_S: begin
                add_counter         <= add_counter + 2'd1;
                (* parallel_case, full_case *)
                case(add_counter)
                  2'd0: bcd_data[27:12] <= (bcd_data[15:12] > 4'd4)? (bcd_data[27:12] + 16'd3): bcd_data[27:12];
                  2'd1: bcd_data[27:16] <= (bcd_data[19:16] > 4'd4)? (bcd_data[27:16] + 12'd3): bcd_data[27:16];
                  2'd2: bcd_data[27:20] <= (bcd_data[23:20] > 4'd4)? (bcd_data[27:20] + 8'd3): bcd_data[27:20];
                  2'd3: bcd_data[27:24] <= (bcd_data[27:24] > 4'd4)? (bcd_data[27:24] + 4'd3): bcd_data[27:24];
                endcase
                if(add_counter == 2'd3)
                    state_bcd       <= SHIFT_S;
            end
            SHIFT_S: begin
                sh_counter          <= sh_counter + 4'd1;
                bcd_data            <= bcd_data << 1;
                
                if(sh_counter == 4'd11) begin
                    bcd_out_valid   <= 1'b1;
                    state_bcd       <= IDLE_S;
                end
                else
                    state_bcd       <= ADD_S;
            end
            default: begin
                state_bcd           <= IDLE_S;
            end
          endcase
        end
    end
    assign bcd_out                  = bcd_data[27:12];
    assign ready                    = state_bcd == IDLE_S;
endmodule