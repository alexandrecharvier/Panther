// Copyright 2014-2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// ============================================================================= //
// Company:        Multitherman Laboratory @ DEIS - University of Bologna        //
//                    Viale Risorgimento 2 40136                                 //
//                    Bologna - fax 0512093785 -                                 //
//                                                                               //
// Engineer:       Igor Loi - igor.loi@unibo.it                                  //
//                                                                               //
//                                                                               //
// Additional contributions by:                                                  //
//                                                                               //
//                                                                               //
//                                                                               //
// Create Date:    01/02/2014                                                    //
// Design Name:    AXI 4 INTERCONNECT                                            //
// Module Name:    axi_BR_allocator                                              //
// Project Name:   PULP                                                          //
// Language:       SystemVerilog                                                 //
//                                                                               //
// Description:   Backward write Allocator: it performs a round robin arbitr     //
//                between pending write responses from each master port.         //
//                                                                               //
// Revision:                                                                     //
// Revision v0.1 - 01/02/2014 : File Created                                     //
//                                                                               //
//                                                                               //
//                                                                               //
//                                                                               //
//                                                                               //
//                                                                               //
// ============================================================================= //

module axi_BR_allocator #(
    parameter int                   AXI_USER_W     = 6,
    parameter int                   N_INIT_PORT    = 1,
    parameter int                   N_TARG_PORT    = 7,
    parameter int                   AXI_DATA_W     = 64,
    parameter int                   AXI_ID_IN      = 16,
    parameter int                   LOG_N_TARG     = $clog2(N_TARG_PORT),
    parameter int                   LOG_N_INIT     = $clog2(N_INIT_PORT),
    parameter int                   AXI_ID_OUT     = AXI_ID_IN + $clog2(N_TARG_PORT)
)(
  input  logic                                                          clk,
  input  logic                                                          rst_n,

  //AXI BACKWARD read data bus ----------------------------------------------
  input  logic [N_INIT_PORT-1:0][AXI_ID_OUT-1:0]                        rid_i,
  input  logic [N_INIT_PORT-1:0][AXI_DATA_W-1:0]                        rdata_i,
  input  logic [N_INIT_PORT-1:0][ 1:0]                                  rresp_i,
  input  logic [N_INIT_PORT-1:0]                                        rlast_i,   //last transfer in burst
  input  logic [N_INIT_PORT-1:0][AXI_USER_W-1:0]                        ruser_i,   //last transfer in burst
  input  logic [N_INIT_PORT-1:0]                                        rvalid_i,  //slave data valid
  output logic [N_INIT_PORT-1:0]                                        rready_o,   //master ready to accept

  //AXI BACKWARD read data bus ----------------------------------------------
  output  logic [AXI_ID_IN-1:0]                                         rid_o,
  output  logic [AXI_DATA_W-1:0]                                        rdata_o,
  output  logic [ 1:0]                                                  rresp_o,
  output  logic                                                         rlast_o,   //last transfer in burst
  output  logic [AXI_USER_W-1:0]                                        ruser_o,   //last transfer in burst
  output  logic                                                         rvalid_o,  //slave data valid
  input   logic                                                         rready_i,   //master ready to accept

  input   logic                                                         incr_req_i,
  output  logic                                                         full_counter_o,
  output  logic                                                         outstanding_trans_o,

  input   logic                                                         error_req_i,
  output  logic                                                         error_gnt_o,
  input   logic [ 7:0]                                                  error_len_i,
  input   logic [AXI_USER_W-1:0]                                        error_user_i,
  input   logic [AXI_ID_IN-1:0]                                         error_id_i,

  input  logic                                                          sample_ardata_info_i
);

localparam      AUX_WIDTH = AXI_DATA_W + 2 + 1 + AXI_USER_W;








logic [N_INIT_PORT-1:0][AUX_WIDTH-1:0]                          AUX_VECTOR_IN;
logic [AUX_WIDTH-1:0]                                           AUX_VECTOR_OUT;
logic [N_INIT_PORT-1:0][AXI_ID_IN-1:0]                          rid_int;

genvar i;




// -------------------------------------------------------------------------   //
// -------------------------------------------------------------------------   //
//                         TRACK PENDING TRANSACTIONS                          //
// -------------------------------------------------------------------------   //
// -------------------------------------------------------------------------   //
logic   [9:0]                                                   outstanding_counter;
logic                                                           decr_req;
enum logic [1:0]                                                {OPERATIVE, ERROR_SINGLE, ERROR_BURST, GO_ERROR} CS, NS;
logic   [7:0]                                                   CounterBurstCS, CounterBurstNS;
logic   [ 7:0]                                                  error_len_S;
logic   [AXI_USER_W-1:0]                                        error_user_S;
logic   [AXI_ID_IN-1:0]                                         error_id_S;

//OUtput of the ARB tree, to be multiplexed in the FSM
logic [AXI_ID_IN-1:0]                                           rid_ARB_TREE;
logic [AXI_DATA_W-1:0]                                          rdata_ARB_TREE;
logic [ 1:0]                                                    rresp_ARB_TREE;
logic                                                           rlast_ARB_TREE;   //last transfer in burst
logic [AXI_USER_W-1:0]                                          ruser_ARB_TREE;   //last transfer in burst
logic                                                           rvalid_ARB_TREE;  //slave data valid
logic                                                           rready_ARB_TREE;   //master ready to accept




assign outstanding_trans_o = (outstanding_counter == '0) ? 1'b0 : 1'b1;

assign decr_req = rvalid_ARB_TREE & rready_ARB_TREE & rlast_ARB_TREE;

assign full_counter_o = (outstanding_counter == '1) ? 1'b1 : 1'b0;


always_ff @(posedge clk, negedge rst_n)
begin
    if(rst_n == 1'b0)
      outstanding_counter  <= '0;
    else
    begin
      case({incr_req_i, decr_req})
        2'b00: begin  outstanding_counter  <= outstanding_counter; end
        2'b01:
        begin
                if(outstanding_counter != '0)
                    outstanding_counter  <= outstanding_counter - 1'b1;
                else
                    outstanding_counter  <= '0;
        end
        2'b10:
        begin
                if(outstanding_counter != '1)
                    outstanding_counter  <= outstanding_counter + 1'b1;
                else
                    outstanding_counter  <= '1;
        end
        2'b11: begin  outstanding_counter  <= outstanding_counter; end
      endcase
    end
end



always_ff @(posedge clk, negedge rst_n)
begin
  if(rst_n == 1'b0)
  begin
    CS             <= OPERATIVE;
    CounterBurstCS <= '0;
    error_user_S   <= '0;
    error_id_S     <= '0;
    error_len_S    <= '0;
  end
  else
  begin
    CS <= NS;
    CounterBurstCS <= CounterBurstNS;
    if(sample_ardata_info_i)
    begin
        error_user_S  <= error_user_i;
        error_id_S    <= error_id_i;
        error_len_S   <= error_len_i;
    end
  end
end


always_comb
begin
  //default Values
  rid_o           = rid_ARB_TREE;
  rdata_o         = rdata_ARB_TREE;
  rresp_o         = rresp_ARB_TREE;
  rlast_o         = rlast_ARB_TREE;
  ruser_o         = ruser_ARB_TREE;
  rvalid_o        = rvalid_ARB_TREE;
  rready_ARB_TREE = rready_i;

  CounterBurstNS = CounterBurstCS;
  error_gnt_o      = 1'b0;


  case(CS)

    OPERATIVE :
    begin
        CounterBurstNS   = '0;
        rready_ARB_TREE  = rready_i;
        error_gnt_o      = 1'b0;

        if((error_req_i == 1'b1))
        begin

          if(outstanding_trans_o == 1'b0)
          begin
              if(error_len_i == '0)
              begin
                NS = ERROR_SINGLE;
              end
              else
              begin
                NS = ERROR_BURST;
              end
          end
          else
          begin
              NS = GO_ERROR;
          end


        end
        else
        begin
          NS = OPERATIVE;
        end
    end





    GO_ERROR:
    begin

          CounterBurstNS   = '0;
          rready_ARB_TREE  = rready_i;
          error_gnt_o      = 1'b0;

          if(outstanding_trans_o == 1'b0)
          begin
              if(error_len_S == '0)
              begin
                NS = ERROR_SINGLE;
              end
              else
              begin
                NS = ERROR_BURST;
              end
          end
          else
          begin
              NS = GO_ERROR;
          end

    end





    ERROR_SINGLE :
    begin
        rready_ARB_TREE = 1'b0;
        CounterBurstNS = '0;
        error_gnt_o = 1'b1;
        rresp_o     = axi_pkg::RESP_DECERR;
        rdata_o     = { (AXI_DATA_W/32) {32'hDEADBEEF}};
        rvalid_o    = 1'b1;
        ruser_o     = error_user_S;
        rlast_o     = 1'b1;
        rid_o       = error_id_S;

        if(rready_i) begin
          NS = OPERATIVE;
        end else begin
          NS = ERROR_SINGLE;
        end
    end



    ERROR_BURST :
    begin

        rready_ARB_TREE = 1'b0;

        rresp_o     = axi_pkg::RESP_DECERR;
        rdata_o     = { (AXI_DATA_W/32) {32'hDEADBEEF}};
        rvalid_o    = 1'b1;
        ruser_o     = error_user_S;
        rid_o       = error_id_S;

        if(rready_i)
        begin
            if(CounterBurstCS < error_len_i)
            begin
              CounterBurstNS = CounterBurstCS + 1'b1;
              error_gnt_o    = 1'b0;
              rlast_o        = 1'b0;
              NS             = ERROR_BURST;
            end
            else
            begin
              error_gnt_o    = 1'b1;
              CounterBurstNS = '0;
              NS             = OPERATIVE;
              rlast_o        = 1'b1;
            end
        end
        else
        begin
            NS = ERROR_BURST;
            error_gnt_o      = 1'b0;
        end

    end


    default :
    begin
        CounterBurstNS = '0;
        NS             = OPERATIVE;
        error_gnt_o      = 1'b0;
    end



  endcase
end
// -------------------------------------------------------------------------   //
// -------------------------------------------------------------------------   //


assign        { ruser_ARB_TREE, rlast_ARB_TREE, rresp_ARB_TREE, rdata_ARB_TREE}  =  AUX_VECTOR_OUT;


generate

  for(i=0;i<N_INIT_PORT;i++)
  begin : g_aux_vector_binding
      assign AUX_VECTOR_IN[i] =  { ruser_i[i], rlast_i[i], rresp_i[i], rdata_i[i]};
  end

  for(i=0;i<N_INIT_PORT;i++)
  begin : g_rid_vector_binding
      assign rid_int[i] =  rid_i[i][AXI_ID_IN-1:0];
  end




if(N_INIT_PORT == 1)
begin : g_direct_binding
    assign rvalid_ARB_TREE = rvalid_i;
    //assign rvalid_o      = rvalid_i;
    assign AUX_VECTOR_OUT  = AUX_VECTOR_IN;

    assign rid_ARB_TREE   = rid_int;
    //assign rid_o        = rid_int;
    assign rready_o       = rready_i;
end
else
begin : g_arb_tree
    axi_ArbitrationTree
    #(
      .AUX_WIDTH  (AUX_WIDTH),
      .ID_WIDTH   (AXI_ID_IN),
      .N_MASTER   (N_INIT_PORT)
    )
    BR_ARB_TREE
    (
      .clk           (  clk            ),
      .rst_n         (  rst_n          ),

      // ---------------- RESP_SIDE -------
      .data_req_i    (  rvalid_i       ),
      .data_AUX_i    (  AUX_VECTOR_IN  ),
      .data_ID_i     (  rid_int        ),
      .data_gnt_o    (  rready_o       ),

      // Outputs
      .data_req_o    (  rvalid_ARB_TREE  ),
      .data_AUX_o    (  AUX_VECTOR_OUT   ),
      .data_ID_o     (  rid_ARB_TREE     ),
      .data_gnt_i    (  rready_ARB_TREE  ),

      .lock          (1'b0),
      .SEL_EXCLUSIVE ({$clog2(N_INIT_PORT){1'b0}})
    );
end
endgenerate



endmodule
