// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Description: This module is a reset synchronizer with a dedicated reset bypass pin for testmode reset.
// Pro Tip: The wise Dr. Schaffner recommends at least 4 registers!

module rstgen_bypass #(
    parameter int unsigned NumRegs = 4
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic rst_test_mode_ni,
    input  logic test_mode_i,
    output logic rst_no,
    output logic rst_ckg_no,
    output logic init_no
);

    // internal reset
    logic rst_n;

    logic [2*NumRegs-1:0] synch_regs_q;
    // bypass mode
    always_comb begin
        if (test_mode_i == 1'b0) begin
            init_no     = synch_regs_q[  NumRegs-1];
        end else begin
            init_no    = 1'b1;
        end
    end

  hard_mux2 rst_n_hard_mux2
  (
   .i_sel ( test_mode_i      ),
   .i_i0  ( rst_ni           ),
   .i_i1  ( rst_test_mode_ni ),
   .o_z   ( rst_n            )
  );

  hard_mux2 rst_no_hard_mux2
  (
   .i_sel ( test_mode_i               ),
   .i_i0  ( synch_regs_q[  NumRegs-1] ),
   .i_i1  ( rst_test_mode_ni          ),
   .o_z   ( rst_no                    )
  );

  hard_mux2 rst_ckg_no_hard_mux2
  (
   .i_sel ( test_mode_i               ),
   .i_i0  ( synch_regs_q[2*NumRegs-1] ),
   .i_i1  ( rst_test_mode_ni          ),
   .o_z   ( rst_ckg_no                )
  );

    always @(posedge clk_i or negedge rst_n) begin
        if (~rst_n) begin
            synch_regs_q <= 0;
        end else begin
            synch_regs_q <= {synch_regs_q[2*NumRegs-2:0], 1'b1};
        end
    end
    // pragma translate_off
    `ifndef VERILATOR
    initial begin : p_assertions
        if (NumRegs < 1) $fatal(1, "At least one register is required.");
    end
    `endif
    // pragma translate_on
endmodule
