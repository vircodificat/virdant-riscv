`ifdef VERILATOR

// rf::Rf — 32×32 register file for Verilator simulation
// Simple registered register file (combinational read, registered write)
// This matches the original rf.vir behavior for simulation.

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

    // Register 0 (x0) is always 0.
    reg [31:0] x1;
    reg [31:0] x2;
    reg [31:0] x3;
    reg [31:0] x4;
    reg [31:0] x5;
    reg [31:0] x6;
    reg [31:0] x7;
    reg [31:0] x8;
    reg [31:0] x9;
    reg [31:0] x10;
    reg [31:0] x11;
    reg [31:0] x12;
    reg [31:0] x13;
    reg [31:0] x14;
    reg [31:0] x15;
    reg [31:0] x16;
    reg [31:0] x17;
    reg [31:0] x18;
    reg [31:0] x19;
    reg [31:0] x20;
    reg [31:0] x21;
    reg [31:0] x22;
    reg [31:0] x23;
    reg [31:0] x24;
    reg [31:0] x25;
    reg [31:0] x26;
    reg [31:0] x27;
    reg [31:0] x28;
    reg [31:0] x29;
    reg [31:0] x30;
    reg [31:0] x31;

    // Write port
    always @(posedge clock) begin
        if (write) begin
            case (rd)
                5'd1:  x1  <= rd_in;
                5'd2:  x2  <= rd_in;
                5'd3:  x3  <= rd_in;
                5'd4:  x4  <= rd_in;
                5'd5:  x5  <= rd_in;
                5'd6:  x6  <= rd_in;
                5'd7:  x7  <= rd_in;
                5'd8:  x8  <= rd_in;
                5'd9:  x9  <= rd_in;
                5'd10: x10 <= rd_in;
                5'd11: x11 <= rd_in;
                5'd12: x12 <= rd_in;
                5'd13: x13 <= rd_in;
                5'd14: x14 <= rd_in;
                5'd15: x15 <= rd_in;
                5'd16: x16 <= rd_in;
                5'd17: x17 <= rd_in;
                5'd18: x18 <= rd_in;
                5'd19: x19 <= rd_in;
                5'd20: x20 <= rd_in;
                5'd21: x21 <= rd_in;
                5'd22: x22 <= rd_in;
                5'd23: x23 <= rd_in;
                5'd24: x24 <= rd_in;
                5'd25: x25 <= rd_in;
                5'd26: x26 <= rd_in;
                5'd27: x27 <= rd_in;
                5'd28: x28 <= rd_in;
                5'd29: x29 <= rd_in;
                5'd30: x30 <= rd_in;
                5'd31: x31 <= rd_in;
                default: ; // x0 is hardwired to 0
            endcase
        end
    end

    // Read port 1
    assign rs1_out = (rs1 == 5'd0) ? 32'd0 :
                      (rs1 == 5'd1) ? x1 :
                      (rs1 == 5'd2) ? x2 :
                      (rs1 == 5'd3) ? x3 :
                      (rs1 == 5'd4) ? x4 :
                      (rs1 == 5'd5) ? x5 :
                      (rs1 == 5'd6) ? x6 :
                      (rs1 == 5'd7) ? x7 :
                      (rs1 == 5'd8) ? x8 :
                      (rs1 == 5'd9) ? x9 :
                      (rs1 == 5'd10) ? x10 :
                      (rs1 == 5'd11) ? x11 :
                      (rs1 == 5'd12) ? x12 :
                      (rs1 == 5'd13) ? x13 :
                      (rs1 == 5'd14) ? x14 :
                      (rs1 == 5'd15) ? x15 :
                      (rs1 == 5'd16) ? x16 :
                      (rs1 == 5'd17) ? x17 :
                      (rs1 == 5'd18) ? x18 :
                      (rs1 == 5'd19) ? x19 :
                      (rs1 == 5'd20) ? x20 :
                      (rs1 == 5'd21) ? x21 :
                      (rs1 == 5'd22) ? x22 :
                      (rs1 == 5'd23) ? x23 :
                      (rs1 == 5'd24) ? x24 :
                      (rs1 == 5'd25) ? x25 :
                      (rs1 == 5'd26) ? x26 :
                      (rs1 == 5'd27) ? x27 :
                      (rs1 == 5'd28) ? x28 :
                      (rs1 == 5'd29) ? x29 :
                      (rs1 == 5'd30) ? x30 :
                      (rs1 == 5'd31) ? x31 : 32'd0;

    // Read port 2
    assign rs2_out = (rs2 == 5'd0) ? 32'd0 :
                      (rs2 == 5'd1) ? x1 :
                      (rs2 == 5'd2) ? x2 :
                      (rs2 == 5'd3) ? x3 :
                      (rs2 == 5'd4) ? x4 :
                      (rs2 == 5'd5) ? x5 :
                      (rs2 == 5'd6) ? x6 :
                      (rs2 == 5'd7) ? x7 :
                      (rs2 == 5'd8) ? x8 :
                      (rs2 == 5'd9) ? x9 :
                      (rs2 == 5'd10) ? x10 :
                      (rs2 == 5'd11) ? x11 :
                      (rs2 == 5'd12) ? x12 :
                      (rs2 == 5'd13) ? x13 :
                      (rs2 == 5'd14) ? x14 :
                      (rs2 == 5'd15) ? x15 :
                      (rs2 == 5'd16) ? x16 :
                      (rs2 == 5'd17) ? x17 :
                      (rs2 == 5'd18) ? x18 :
                      (rs2 == 5'd19) ? x19 :
                      (rs2 == 5'd20) ? x20 :
                      (rs2 == 5'd21) ? x21 :
                      (rs2 == 5'd22) ? x22 :
                      (rs2 == 5'd23) ? x23 :
                      (rs2 == 5'd24) ? x24 :
                      (rs2 == 5'd25) ? x25 :
                      (rs2 == 5'd26) ? x26 :
                      (rs2 == 5'd27) ? x27 :
                      (rs2 == 5'd28) ? x28 :
                      (rs2 == 5'd29) ? x29 :
                      (rs2 == 5'd30) ? x30 :
                      (rs2 == 5'd31) ? x31 : 32'd0;

    // Initialize registers to 0
    initial begin
        x1 = 32'd0;
        x2 = 32'd0;
        x3 = 32'd0;
        x4 = 32'd0;
        x5 = 32'd0;
        x6 = 32'd0;
        x7 = 32'd0;
        x8 = 32'd0;
        x9 = 32'd0;
        x10 = 32'd0;
        x11 = 32'd0;
        x12 = 32'd0;
        x13 = 32'd0;
        x14 = 32'd0;
        x15 = 32'd0;
        x16 = 32'd0;
        x17 = 32'd0;
        x18 = 32'd0;
        x19 = 32'd0;
        x20 = 32'd0;
        x21 = 32'd0;
        x22 = 32'd0;
        x23 = 32'd0;
        x24 = 32'd0;
        x25 = 32'd0;
        x26 = 32'd0;
        x27 = 32'd0;
        x28 = 32'd0;
        x29 = 32'd0;
        x30 = 32'd0;
        x31 = 32'd0;
    end

endmodule

`endif
