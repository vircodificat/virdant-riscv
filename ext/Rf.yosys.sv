`ifdef YOSYS

// rf::Rf — RV32I register file using 4× SB_RAM40_4K (ICE40 block RAM)
//
// Two independent read ports (rs1, rs2) and one write port (rd) are provided
// by duplicating the storage array: each half (lo/hi 16-bit) has a dedicated
// BRAM per read port, with all four BRAMs updated simultaneously on a write.
//
//   BRAMs used:
//     bram_lo_rs1  bits[15: 0]  read by rs1
//     bram_hi_rs1  bits[31:16]  read by rs1
//     bram_lo_rs2  bits[15: 0]  read by rs2
//     bram_hi_rs2  bits[31:16]  read by rs2
//
// SB_RAM40_4K is a 4096-bit true dual-port BRAM.  In 256×16 mode
// (READ_MODE=0, WRITE_MODE=0) it holds 256 16-bit words; we use entries
// 0–31 for x0–x31.  x0 is never written and reads of x0 always return 0.
//
// Reads are synchronous (RDATA is registered): callers must present the
// source-register address one cycle before the data is needed.

module \rf::Rf (
    input  wire            clock,
    input  wire     [4:0]  rd,
    input  wire     [4:0]  rs1,
    input  wire     [4:0]  rs2,
    input  wire    [31:0]  rd_in,
    input  wire            write,
    output wire    [31:0]  rs1_out,
    output wire    [31:0]  rs2_out
); /* verilator public_module */

    // ----------------------------------------------------------------
    // x0 gating
    // ----------------------------------------------------------------
    wire valid_rd  = (rd  != 5'd0);   // suppress writes to x0
    wire valid_rs1 = (rs1 != 5'd0);   // suppress reads  of x0
    wire valid_rs2 = (rs2 != 5'd0);

    // Write enable: only when the instruction requests a write and rd != x0.
    wire we = write & valid_rd;

    // ----------------------------------------------------------------
    // Register the read-valid flags so we can gate the BRAM output
    // (RDATA holds the previous word when RE=0; we must output 0 for x0).
    // ----------------------------------------------------------------
    reg read1_q, read2_q;
    always @(posedge clock) begin
        read1_q <= valid_rs1;
        read2_q <= valid_rs2;
    end

    // ----------------------------------------------------------------
    // BRAM read-data wires (updated one cycle after RADDR/RE presented)
    // ----------------------------------------------------------------
    wire [15:0] lo_rs1_data, hi_rs1_data;
    wire [15:0] lo_rs2_data, hi_rs2_data;

    // ----------------------------------------------------------------
    // bits[15:0] — read port 1 (rs1)
    // ----------------------------------------------------------------
    SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0)) bram_lo_rs1 (
        .RCLK  (clock),
        .RCLKE (1'b1),
        .RE    (valid_rs1),
        .RADDR ({6'd0, rs1}),
        .RDATA (lo_rs1_data),
        .WCLK  (clock),
        .WCLKE (1'b1),
        .WE    (we),
        .WADDR ({6'd0, rd}),
        .WDATA (rd_in[15:0]),
        .MASK  (16'h0000)       // 0 = write all bits
    );

    // ----------------------------------------------------------------
    // bits[31:16] — read port 1 (rs1)
    // ----------------------------------------------------------------
    SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0)) bram_hi_rs1 (
        .RCLK  (clock),
        .RCLKE (1'b1),
        .RE    (valid_rs1),
        .RADDR ({6'd0, rs1}),
        .RDATA (hi_rs1_data),
        .WCLK  (clock),
        .WCLKE (1'b1),
        .WE    (we),
        .WADDR ({6'd0, rd}),
        .WDATA (rd_in[31:16]),
        .MASK  (16'h0000)
    );

    // ----------------------------------------------------------------
    // bits[15:0] — read port 2 (rs2)
    // ----------------------------------------------------------------
    SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0)) bram_lo_rs2 (
        .RCLK  (clock),
        .RCLKE (1'b1),
        .RE    (valid_rs2),
        .RADDR ({6'd0, rs2}),
        .RDATA (lo_rs2_data),
        .WCLK  (clock),
        .WCLKE (1'b1),
        .WE    (we),
        .WADDR ({6'd0, rd}),
        .WDATA (rd_in[15:0]),
        .MASK  (16'h0000)
    );

    // ----------------------------------------------------------------
    // bits[31:16] — read port 2 (rs2)
    // ----------------------------------------------------------------
    SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0)) bram_hi_rs2 (
        .RCLK  (clock),
        .RCLKE (1'b1),
        .RE    (valid_rs2),
        .RADDR ({6'd0, rs2}),
        .RDATA (hi_rs2_data),
        .WCLK  (clock),
        .WCLKE (1'b1),
        .WE    (we),
        .WADDR ({6'd0, rd}),
        .WDATA (rd_in[31:16]),
        .MASK  (16'h0000)
    );

    // ----------------------------------------------------------------
    // Outputs: force 0 when the previous cycle read x0 (read1_q/read2_q=0)
    // ----------------------------------------------------------------
    assign rs1_out = read1_q ? {hi_rs1_data, lo_rs1_data} : 32'd0;
    assign rs2_out = read2_q ? {hi_rs2_data, lo_rs2_data} : 32'd0;

endmodule

`endif
