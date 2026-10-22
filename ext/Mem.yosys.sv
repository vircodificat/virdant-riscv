`ifdef YOSYS

// mem::Mem  — 16384×32 data RAM  — 2× SB_SPRAM256KA (low / high 16-bit halves)
// mem::Csrs — 4096×32  CSR file  — 2× SB_SPRAM256KA (ADDRESS[13:12] = 2'b00)
//
// SB_SPRAM256KA read outputs are registered on the rising edge of CLOCK.
// The original modules had combinational (asynchronous) reads; callers must
// present the address one cycle before the data is needed.
//
// SB_SPRAM256KA has no bitstream-initializable content.  The original
// mem::Csrs `initial begin mem[12'hF14] = 32'd0; end` (mhartid = 0) is
// dropped; an explicit write during reset is required if a non-zero power-up
// value is possible.

module \mem::Mem (
    input  wire             clock,
    input  wire     [31:0]  addr,
    input  wire     [31:0]  data_in,
    input  wire             read,
    input  wire             write,
    output reg      [31:0]  data_out
); /* verilator public_module */

    // Word address: addr[15:2] selects one of 16384 32-bit words.
    wire [13:0] waddr = addr[15:2];
    // Activate the SPRAM only when actually reading or writing.
    wire        cs    = read | write;

    wire [15:0] lo_out, hi_out;

    // Lower 16 bits of each 32-bit word.
    SB_SPRAM256KA spram_lo (
        .ADDRESS   (waddr),
        .DATAIN    (data_in[15:0]),
        .MASKWREN  (4'b1111),
        .WREN      (write),
        .CHIPSELECT(cs),
        .CLOCK     (clock),
        .STANDBY   (1'b0),
        .SLEEP     (1'b0),
        .POWEROFF  (1'b1),
        .DATAOUT   (lo_out)
    );

    // Upper 16 bits of each 32-bit word.
    SB_SPRAM256KA spram_hi (
        .ADDRESS   (waddr),
        .DATAIN    (data_in[31:16]),
        .MASKWREN  (4'b1111),
        .WREN      (write),
        .CHIPSELECT(cs),
        .CLOCK     (clock),
        .STANDBY   (1'b0),
        .SLEEP     (1'b0),
        .POWEROFF  (1'b1),
        .DATAOUT   (hi_out)
    );

    // SPRAM read data arrives one cycle after the address is presented.
    // Preserve the original "output 0 when not reading" semantic using the
    // registered read enable.
    reg read_q;
    always @(posedge clock)
        read_q <= read;

    always @(*) begin
        if (read_q)
            data_out = {hi_out, lo_out};
        else
            data_out = 32'd0;
    end

endmodule

module \mem::Csrs (
    input  wire             clock,
    input  wire     [11:0]  addr,
    input  wire     [31:0]  data_in,
    output wire     [31:0]  data_out,
    input  wire             write
); /* verilator public_module */

    // 4096 CSR addresses mapped into the low quarter of two SB_SPRAM256KA
    // blocks (ADDRESS[13:12] = 2'b00; upper three-quarters are unused).
    wire [13:0] waddr = {2'b00, addr};
    wire [15:0] lo_out, hi_out;

    SB_SPRAM256KA spram_lo (
        .ADDRESS   (waddr),
        .DATAIN    (data_in[15:0]),
        .MASKWREN  (4'b1111),
        .WREN      (write),
        .CHIPSELECT(1'b1),
        .CLOCK     (clock),
        .STANDBY   (1'b0),
        .SLEEP     (1'b0),
        .POWEROFF  (1'b1),
        .DATAOUT   (lo_out)
    );

    SB_SPRAM256KA spram_hi (
        .ADDRESS   (waddr),
        .DATAIN    (data_in[31:16]),
        .MASKWREN  (4'b1111),
        .WREN      (write),
        .CHIPSELECT(1'b1),
        .CLOCK     (clock),
        .STANDBY   (1'b0),
        .SLEEP     (1'b0),
        .POWEROFF  (1'b1),
        .DATAOUT   (hi_out)
    );

    // mcycle/cycle (0xB00/0xC00) read as a free-running cycle counter so
    // software can time itself (used by the Dhrystone port).  Writes to
    // those addresses land in the SPRAM and are ignored on read.
    reg [31:0] cycle_counter;

    always @(posedge clock) begin
        cycle_counter <= cycle_counter + 32'd1;
    end

    assign data_out = (addr == 12'hB00 || addr == 12'hC00)
                    ? cycle_counter : {hi_out, lo_out};

endmodule

`endif
