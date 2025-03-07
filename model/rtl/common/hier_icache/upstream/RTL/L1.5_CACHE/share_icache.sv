// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

import hier_icache_pkg::*;

module share_icache
#(
   parameter int N_BANKS                = 32,
   parameter int SET_ASSOCIATIVE        = 4,
   parameter int CACHE_LINE             = 4,        // WORDS in each cache line allowed value are 1 - 2 - 4 - 8
   parameter int CACHE_SIZE             = 16384,    // Byte
   parameter int CACHE_ID               = 1,
   parameter int FIFO_DEPTH             = 2,

   parameter int ICACHE_DATA_WIDTH      = 128,
   parameter int ICACHE_ID_WIDTH        = 16,
   parameter int ICACHE_ADDR_WIDTH      = 32,

   parameter     DIRECT_MAPPED_FEATURE  = "DISABLED",
   parameter bit PRIVATE_ICACHE         = 1,

   parameter int TAGRAM_ADDR_WIDTH      = 32,
   parameter int TAGRAM_DATA_WIDTH      = 32,
   parameter int DATARAM_ADDR_WIDTH     = 32,
   parameter int DATARAM_DATA_WIDTH     = 128,
   parameter int DATARAM_BE_WIDTH       = 16,
   parameter int REDUCE_TAG_WIDTH       = 1,

   parameter int AXI_ID                 = 10,
   parameter int AXI_ADDR               = 32,
   parameter int AXI_DATA               = 64,
   parameter int AXI_USER               = 6,

   parameter bit USE_REDUCED_TAG        = 1    // 1 | 0
)
(
   // -------------------------------------------------------------------------------------
   // I/O Port Declarations ---------------------------------------------------------------
   // -------------------------------------------------------------------------------------
   input logic                                                clk,
   input logic                                                rst_n,
   input logic                                                test_en_i,
   // -------------------------------------------------------------------------------------
   // SHARED_ICACHE_INTERCONNECT Port Declarations ----------------------------------------
   // -------------------------------------------------------------------------------------
   input  logic                                                fetch_req_i,
   output logic                                                fetch_grant_o,
   input  logic [ICACHE_ADDR_WIDTH-1:0]                        fetch_addr_i,
   input  logic [ICACHE_ID_WIDTH-1:0]                          fetch_ID_i,

   output logic [ICACHE_DATA_WIDTH-1:0]                        fetch_r_rdata_o,
   output logic                                                fetch_r_valid_o,
   output logic [ICACHE_ID_WIDTH-1:0]                          fetch_r_ID_o,

   // -------------------------------------------------------------------------------------
   // AXI INIT Port Declarations ----------------------------------------------------------
   // -------------------------------------------------------------------------------------

   //AXI write address bus -------------- // // -------------------------------------------
   output logic [AXI_ID-1:0]                                   init_awid_o,        //
   output logic [AXI_ADDR-1:0]                                 init_awaddr_o,      //
   output logic [ 7:0]                                         init_awlen_o,       // burst length is 1 + (0 - 15)
   output logic [ 2:0]                                         init_awsize_o,      // size of each transfer in burst
   output logic [ 1:0]                                         init_awburst_o,     // for bursts>1, accept only incr burst=01
   output logic                                                init_awlock_o,      // only normal access supported axs_awlock=00
   output logic [ 3:0]                                         init_awcache_o,     //
   output logic [ 2:0]                                         init_awprot_o,      //
   output logic [ 3:0]                                         init_awregion_o,    //
   output logic [ AXI_USER-1:0]                                init_awuser_o,      //
   output logic [ 3:0]                                         init_awqos_o,       //
   output logic                                                init_awvalid_o,     // master addr valid
   input  logic                                                init_awready_i,     // slave ready to accept
   // ---------------------------------------------------------------

   //AXI write data bus -------------- // // --------------
   output logic  [AXI_DATA-1:0]                                init_wdata_o,
   output logic  [AXI_DATA/8-1:0]                              init_wstrb_o,   //1 strobe per byte
   output logic                                                init_wlast_o,   //last transfer in burst
   output logic  [ AXI_USER-1:0]                               init_wuser_o,   //user sideband signals
   output logic                                                init_wvalid_o,  //master data valid
   input  logic                                                init_wready_i,  //slave ready to accept
   // ---------------------------------------------------------------

   //AXI BACKWARD write response bus -------------- // // --------------
   input  logic  [AXI_ID-1:0]                                  init_bid_i,
   input  logic  [ 1:0]                                        init_bresp_i,
   input  logic  [ AXI_USER-1:0]                               init_buser_i,
   input  logic                                                init_bvalid_i,
   output logic                                                init_bready_o,
   // ---------------------------------------------------------------



   //AXI read address bus -------------------------------------------
   output  logic [AXI_ID-1:0]                                  init_arid_o,
   output  logic [AXI_ADDR-1:0]                                init_araddr_o,
   output  logic [ 7:0]                                        init_arlen_o,   //burst length - 1 to 16
   output  logic [ 2:0]                                        init_arsize_o,  //size of each transfer in burst
   output  logic [ 1:0]                                        init_arburst_o, //for bursts>1, accept only incr burst=01
   output  logic                                               init_arlock_o,  //only normal access supported axs_awlock=00
   output  logic [ 3:0]                                        init_arcache_o,
   output  logic [ 2:0]                                        init_arprot_o,
   output  logic [ 3:0]                                        init_arregion_o,        //
   output  logic [ AXI_USER-1:0]                               init_aruser_o,        //
   output  logic [ 3:0]                                        init_arqos_o,        //
   output  logic                                               init_arvalid_o, //master addr valid
   input logic                                                 init_arready_i, //slave ready to accept
   // ---------------------------------------------------------------


   //AXI BACKWARD read data bus ----------------------------------------------
   input  logic [AXI_ID-1:0]                                   init_rid_i,
   input  logic [AXI_DATA-1:0]                                 init_rdata_i,
   input  logic [ 1:0]                                         init_rresp_i,
   input  logic                                                init_rlast_i,   //last transfer in burst
   input  logic [ AXI_USER-1:0]                                init_ruser_i,
   input  logic                                                init_rvalid_i,  //slave data valid
   output logic                                                init_rready_o,  //master ready to accept


   // Control ports
   input  logic                                                ctrl_req_enable_icache_i,
   output logic                                                ctrl_ack_enable_icache_o,

   input  logic                                                ctrl_req_disable_icache_i,
   output logic                                                ctrl_ack_disable_icache_o,

   input  logic                                                ctrl_req_flush_icache_i,
   output logic                                                ctrl_ack_flush_icache_o,

   output logic                                                ctrl_pending_trans_icache_o,

   input  logic                                                ctrl_sel_flush_req_i,
   input  logic [31:0]                                         ctrl_sel_flush_addr_i,
   output logic                                                ctrl_sel_flush_ack_o,

   output logic [31:0]                                         ctrl_hit_count_icache_o,
   output logic [31:0]                                         ctrl_trans_count_icache_o,
   output logic [31:0]                                         ctrl_miss_count_icache_o,
   input  logic                                                ctrl_clear_regs_icache_i,
   input  logic                                                ctrl_enable_regs_icache_i,

   // Signals connected to tagram
   output logic [TAGRAM_ADDR_WIDTH-1:0]                                 TAG_addr_o,
   output logic [SET_ASSOCIATIVE-1:0]                                   TAG_req_o,
   output logic                                                         TAG_write_o,
   output logic [TAGRAM_DATA_WIDTH-1:0]                                 TAG_wdata_o,
   input  logic [SET_ASSOCIATIVE-1:0] [TAGRAM_DATA_WIDTH-1:0]           TAG_rdata_i,

   // Signals connected to dataram
   output logic [DATARAM_ADDR_WIDTH-1:0]                                DATA_addr_o,
   output logic [SET_ASSOCIATIVE-1:0]                                   DATA_req_o,
   output logic                                                         DATA_write_o,
   output logic [DATARAM_DATA_WIDTH-1:0]                                DATA_wdata_o,
   output logic [DATARAM_BE_WIDTH-1:0]                                  DATA_be_o,
   input  logic [SET_ASSOCIATIVE-1:0][DATARAM_DATA_WIDTH-1:0]           DATA_rdata_i
);


   // Multiplexer that select read data between the N WAYS (NOT USED IF CACHE IS DIRECT MAPPED
   logic [$clog2(SET_ASSOCIATIVE)-1:0]                           DATA_way_muxsel;
   logic [DATARAM_DATA_WIDTH-1:0]                                DATA_rdata_int;

   logic                                                         bypass_icache;



   //AXI read address bus --------------------------------------------------------
   logic [AXI_ID-1:0]                                            init_arid_int;
   logic [AXI_ADDR-1:0]                                          init_araddr_int;
   logic [ 7:0]                                                  init_arlen_int;
   logic [ 2:0]                                                  init_arsize_int;
   logic [ 1:0]                                                  init_arburst_int;
   logic                                                         init_arlock_int;
   logic [ 3:0]                                                  init_arcache_int;
   logic [ 2:0]                                                  init_arprot_int;
   logic [ 3:0]                                                  init_arregion_int;
   logic [ AXI_USER-1:0]                                         init_aruser_int;
   logic [ 3:0]                                                  init_arqos_int;
   logic                                                         init_arvalid_int;
   logic                                                         init_arready_int;
   // -----------------------------------------------------------------------------


   //AXI BACKWARD read data bus ----------------------------------------------
   logic [AXI_ID-1:0]                                            init_rid_int;
   logic [CACHE_LINE-1:0][ICACHE_DATA_WIDTH-1:0]                 init_rdata_int;
   logic [1:0][AXI_DATA-1:0]                                     init_rdata_delay;
   logic                                                         init_rdata_index;
   logic [ 1:0]                                                  init_rresp_int;
   logic                                                         init_rlast_int;
   logic [ AXI_USER-1:0]                                         init_ruser_int;
   logic                                                         init_rvalid_int;
   logic                                                         init_rready_int;


   logic [AXI_ID-1:0]                                            init_rid_mux;
   logic [CACHE_LINE-1:0][ICACHE_DATA_WIDTH-1:0]                 init_rdata_mux;
   logic [ 1:0]                                                  init_rresp_mux;
   logic                                                         init_rlast_mux;
   logic [ AXI_USER-1:0]                                         init_ruser_mux;
   logic                                                         init_rvalid_mux;
   logic                                                         init_rready_mux;

   share_icache_controller
   #(
      .SET_ASSOCIATIVE          ( SET_ASSOCIATIVE        ),
      .CACHE_LINE               ( CACHE_LINE             ),        // WORDS in each cache line allowed value are 1 - 2 - 4 - 8
      .CACHE_SIZE               ( CACHE_SIZE             ),        // In Byte
      .N_BANKS                  ( N_BANKS                ),
      .ICACHE_DATA_WIDTH        ( ICACHE_DATA_WIDTH      ),
      .ICACHE_ID_WIDTH          ( ICACHE_ID_WIDTH        ),
      .ICACHE_ADDR_WIDTH        ( ICACHE_ADDR_WIDTH      ),

      .TAGRAM_ADDR_WIDTH        ( TAGRAM_ADDR_WIDTH      ),
      .TAGRAM_DATA_WIDTH        ( TAGRAM_DATA_WIDTH      ),
      .DATARAM_ADDR_WIDTH       ( DATARAM_ADDR_WIDTH     ),
      .DATARAM_DATA_WIDTH       ( DATARAM_DATA_WIDTH     ),
      .DATARAM_BE_WIDTH         ( DATARAM_BE_WIDTH       ),
      .CACHE_ID                 ( CACHE_ID               ),

      .DIRECT_MAPPED_FEATURE    ( DIRECT_MAPPED_FEATURE  ),

      .AXI_ADDR                 ( AXI_ADDR               ),
      .AXI_DATA                 ( AXI_DATA               ),
      .AXI_ID                   ( AXI_ID                 ),
      .AXI_USER                 ( AXI_USER               ),
      .USE_REDUCED_TAG          ( USE_REDUCED_TAG        ),
      .REDUCE_TAG_WIDTH         ( REDUCE_TAG_WIDTH       )
   )
   u_icache_controller
   (
      // ---------------------------------------------------------------
      // I/O Port Declarations -----------------------------------------
      // ---------------------------------------------------------------
      .clk                       (  clk             ),
      .rst_n                     (  rst_n           ),
      .test_en_i                 (  test_en_i           ),


      // ---------------------------------------------------------------
      // SHARED_ICACHE_INTERCONNECT Port Declarations -----------------------------------------
      // ---------------------------------------------------------------
      .fetch_req_i               (  fetch_req_i     ),
      .fetch_grant_o             (  fetch_grant_o   ),
      .fetch_addr_i              (  fetch_addr_i    ),
      .fetch_ID_i                (  fetch_ID_i      ),

      .fetch_r_rdata_o           (  fetch_r_rdata_o ),
      .fetch_r_valid_o           (  fetch_r_valid_o ),
      .fetch_r_ID_o              (  fetch_r_ID_o    ),


      // Signals connected to tagram
      .TAG_addr_o                (  TAG_addr_o      ),
      .TAG_req_o                 (  TAG_req_o       ),
      .TAG_write_o               (  TAG_write_o     ),
      .TAG_wdata_o               (  TAG_wdata_o     ),
      .TAG_rdata_i               (  TAG_rdata_i     ),

      // Signals connected to dataram
      .DATA_addr_o               (  DATA_addr_o     ),
      .DATA_req_o                (  DATA_req_o      ),
      .DATA_write_o              (  DATA_write_o    ),
      .DATA_wdata_o              (  DATA_wdata_o    ),
      .DATA_be_o                 (  DATA_be_o       ),
      .DATA_rdata_i              (  DATA_rdata_int  ),

      .DATA_way_muxsel_o         ( DATA_way_muxsel  ), // USED only for MultiWay CACHES

      .bypass_icache_o           ( bypass_icache    ),

      // ---------------------------------------------------------------
      // AXI4 INITIATOR Port Declarations -----------------------------------------
      // ---------------------------------------------------------------
      //AXI read address bus -------------------------------------------
      .init_arid_o               ( init_arid_int     ),
      .init_araddr_o             ( init_araddr_int   ),
      .init_arlen_o              ( init_arlen_int    ),
      .init_arsize_o             ( init_arsize_int   ),
      .init_arburst_o            ( init_arburst_int  ),
      .init_arlock_o             ( init_arlock_int   ),
      .init_arcache_o            ( init_arcache_int  ),
      .init_arprot_o             ( init_arprot_int   ),
      .init_arregion_o           ( init_arregion_int ),
      .init_aruser_o             ( init_aruser_int   ),
      .init_arqos_o              ( init_arqos_int    ),
      .init_arvalid_o            ( init_arvalid_int  ),
      .init_arready_i            ( init_arready_int  ),

      //AXI BACKWARD read data bus ----------------------------------------------
      .init_rid_i                ( init_rid_mux      ),
      .init_rdata_i              ( init_rdata_mux    ),
      .init_rresp_i              ( init_rresp_mux    ),
      .init_ruser_i              ( init_ruser_mux    ),
      .init_rvalid_i             ( init_rvalid_mux   ),
      .init_rready_o             ( init_rready_mux   ),

      // Control ports
      .ctrl_req_enable_icache_i    ( ctrl_req_enable_icache_i    ),
      .ctrl_ack_enable_icache_o    ( ctrl_ack_enable_icache_o    ),
      .ctrl_req_disable_icache_i   ( ctrl_req_disable_icache_i   ),
      .ctrl_ack_disable_icache_o   ( ctrl_ack_disable_icache_o   ),
      .ctrl_pending_trans_icache_o ( ctrl_pending_trans_icache_o ),

      .ctrl_req_flush_icache_i     ( ctrl_req_flush_icache_i     ),
      .ctrl_ack_flush_icache_o     ( ctrl_ack_flush_icache_o     ),

      .ctrl_sel_flush_req_i        ( ctrl_sel_flush_req_i         ),
      .ctrl_sel_flush_addr_i       ( ctrl_sel_flush_addr_i        ),
      .ctrl_sel_flush_ack_o        ( ctrl_sel_flush_ack_o         ),
      .ctrl_hit_count_icache_o       ( ctrl_hit_count_icache_o     ),
      .ctrl_trans_count_icache_o     ( ctrl_trans_count_icache_o   ),
      .ctrl_miss_count_icache_o      ( ctrl_miss_count_icache_o    ),
      .ctrl_clear_regs_icache_i      ( ctrl_clear_regs_icache_i    ),
      .ctrl_enable_regs_icache_i     ( ctrl_enable_regs_icache_i   )
   );

   assign init_rid_int   = '0;
   assign init_rresp_int = '0;
   assign init_ruser_int = '0;

generate
    case(ICACHE_DATA_WIDTH)
    128,256,512:
    begin
        assign init_rid_mux    = init_rid_int;
        assign init_rdata_mux  = init_rdata_int;
        assign init_rresp_mux  = init_rresp_int;
        assign init_ruser_mux  = init_ruser_int;
        assign init_rvalid_mux = init_rvalid_int;
        assign init_rready_o   = init_rready_int;
    end
    32,64:
    begin
        assign init_rid_mux    = ( bypass_icache ) ?   init_rid_i      : init_rid_int;
        assign init_rdata_mux  = ( bypass_icache ) ?   init_rdata_i    : init_rdata_int;
        assign init_rresp_mux  = ( bypass_icache ) ?   init_rresp_i    : init_rresp_int;
        assign init_ruser_mux  = ( bypass_icache ) ?   init_ruser_i    : init_ruser_int;
        assign init_rvalid_mux = ( bypass_icache ) ?   init_rvalid_i   : init_rvalid_int;
        assign init_rready_o   = ( bypass_icache ) ?   init_rready_mux : init_rready_int;
    end
    endcase
endgenerate

   `ifndef SYNTHESIS
   property valid_2_ready;
      @(posedge clk)
        disable iff (~rst_n)
          $rose(init_rvalid_int) |-> ##[0:1] init_rready_mux;
   endproperty

   property ready_2_valid;
      @(posedge clk)
        disable iff (~rst_n)
          $rose(init_rready_mux) |=> (~init_rvalid_int);
   endproperty

   assert property (valid_2_ready)
     else
       $display("@%0dns shared icache valid_2_ready assertion Failed", $time);

   assert property (ready_2_valid)
     else
       $display("@%0dns shared icache ready_2_valid assertion Failed", $time);
   `endif

   // Wait two 64 bits to combine 128 data//
   assign init_rdata_int  = {init_rdata_delay[1], init_rdata_delay[0]};
   assign init_rready_int = ~init_rvalid_int;

   always_ff @(posedge clk, negedge rst_n)
     begin
        if(~rst_n)
          begin
             init_rdata_delay <= '0;
             init_rvalid_int  <= '0;

             init_rdata_index <= '0;
          end
        else
          begin
             if(init_rvalid_i & init_rready_int)
               begin
                  init_rdata_delay[init_rdata_index] <= init_rdata_i;
                  init_rdata_index                   <=  ~init_rdata_index;
               end

             if(init_rvalid_i & init_rlast_i)
               begin
                  init_rvalid_int  <= 1'b1;
               end else if (init_rready_mux) begin
                  init_rvalid_int  <= 1'b0;
               end else begin
                  init_rvalid_int  <= init_rvalid_int;
               end
          end
     end

   //Adress Request FIFO
   axi_ar_buffer
   #(
       .ID_WIDTH     (AXI_ID),
       .ADDR_WIDTH   (AXI_ADDR),
       .USER_WIDTH   (AXI_USER),
       .BUFFER_DEPTH (2)
   )
   axi_ar_buffer_i
   (
     .clk_i           (   clk             ),
     .rst_ni          (   rst_n           ),
     .test_en_i       ( test_en_i         ),

     .slave_valid_i   ( init_arvalid_int  ),
     .slave_addr_i    ( init_araddr_int   ),
     .slave_prot_i    ( init_arprot_int   ),
     .slave_region_i  ( init_arregion_int ),
     .slave_len_i     ( init_arlen_int    ),
     .slave_size_i    ( init_arsize_int   ),
     .slave_burst_i   ( init_arburst_int  ),
     .slave_lock_i    ( init_arlock_int   ),
     .slave_cache_i   ( init_arcache_int  ),
     .slave_qos_i     ( init_arqos_int    ),
     .slave_id_i      ( init_arid_int     ),
     .slave_user_i    ( init_aruser_int   ),
     .slave_ready_o   ( init_arready_int  ),

     .master_valid_o  ( init_arvalid_o    ),
     .master_addr_o   ( init_araddr_o     ),
     .master_prot_o   ( init_arprot_o     ),
     .master_region_o ( init_arregion_o   ),
     .master_len_o    ( init_arlen_o      ),
     .master_size_o   ( init_arsize_o     ),
     .master_burst_o  ( init_arburst_o    ),
     .master_lock_o   ( init_arlock_o     ),
     .master_cache_o  ( init_arcache_o    ),
     .master_qos_o    ( init_arqos_o      ),
     .master_id_o     ( init_arid_o       ),
     .master_user_o   ( init_aruser_o     ),
     .master_ready_i  ( init_arready_i    )
   );


  if(DIRECT_MAPPED_FEATURE == "ENABLED")
      assign DATA_rdata_int  = DATA_rdata_i[0];
  else
      assign DATA_rdata_int  = DATA_rdata_i[DATA_way_muxsel];



  // Bindo to Zero WRITE, ADDRESS WRITE and BACKWARD WRITE AXI CHANNELS
  assign init_awid_o        =  '0;
  assign init_awaddr_o      =  '0;
  assign init_awlen_o       =  '0;
  assign init_awsize_o      =  '0;
  assign init_awburst_o     =  '0;
  assign init_awlock_o      = 1'b0;
  assign init_awcache_o     =  '0;
  assign init_awprot_o      =  '0;
  assign init_awregion_o    =  '0;
  assign init_awuser_o      =  '0;
  assign init_awqos_o       =  '0;
  assign init_awvalid_o     = 1'b0;
  assign init_wdata_o       =  '0;
  assign init_wstrb_o       =  '0;
  assign init_wlast_o       = 1'b0;
  assign init_wuser_o       =  '0;
  assign init_wvalid_o      = 1'b0;
  assign init_bready_o      = 1'b0;

endmodule
