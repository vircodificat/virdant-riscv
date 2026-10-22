`ifdef VERILATOR

module \mem::Mem (
    input  wire             clock,
    input  wire     [31:0]  addr,
    input  wire     [31:0]  data_in,
    input  wire             read,
    input  wire             write,
    input  wire     [3:0]   sel,
    output reg      [31:0]  data_out
); /* verilator public_module */
    // 64KiB: 16384 entries * 4 bytes = 64 * 1024 bytes
    reg [31:0] mem[16384] /* verilator public */;

    always @(*) begin
        if (read) begin
            data_out = mem[addr[15:2]];
//            $display("Mem read: [0x%x] >= 0x%x", addr, data_out);
        end else begin
            data_out = 32'd0;
        end
    end

    always @(posedge clock) begin
        if (write) begin
//            $display("Mem write: [0x%x] <= 0x%x", addr, data_in);
            mem[addr[15:2]] <= {
                sel[3] ? data_in[31:24] : mem[addr[15:2]][31:24],
                sel[2] ? data_in[23:16] : mem[addr[15:2]][23:16],
                sel[1] ? data_in[15:8]  : mem[addr[15:2]][15:8],
                sel[0] ? data_in[7:0]   : mem[addr[15:2]][7:0]
            };
        end
    end
endmodule

module \mem::Csrs (
    input  wire             clock,
    input  wire     [11:0]  addr,
    input  wire     [31:0]  data_in,
    output reg      [31:0]  data_out,
    input  wire             write
); /* verilator public_module */
    reg [31:0] mem[4096] /* verilator public */;

    // mcycle/cycle (0xB00/0xC00) read as a free-running cycle counter so
    // software can time itself (used by the Dhrystone port).  Writes to
    // those addresses land in the RAM and are ignored on read.
    reg [31:0] cycle_counter;

    assign data_out = (addr == 12'hB00 || addr == 12'hC00)
                    ? cycle_counter : mem[addr];

    always @(posedge clock) begin
        cycle_counter <= cycle_counter + 32'd1;
        if (write) begin
            mem[addr] = data_in;
//            $display("CSR: 0x%x <= [0x%x] <= 0x%x", data_out, addr, data_in);
        end
    end

    initial begin
        mem[12'hF14] = 32'd0;
        cycle_counter = 32'd0;
    end

endmodule

`endif
