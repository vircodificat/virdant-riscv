module \mem::Mem (
    input  wire             clock,
    input  wire     [31:0]  addr,
    input  wire     [31:0]  data_in,
    input  wire             read,
    input  wire             write,
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
            mem[addr[15:2]] <= data_in;
        end
    end
endmodule

module \mem::Csrs (
    input  wire             clock,
    input  wire     [11:0]  addr,
    input  wire     [31:0]  data_in,
    output reg      [31:0]  data_out,
    input  wire             read_write
); /* verilator public_module */
    reg [31:0] mem[4096] /* verilator public */;

    always @(posedge clock) begin
        if (read_write) begin
            data_out = mem[addr];
            mem[addr] = data_in;
//            $display("Mem read: [0x%x] >= 0x%x", addr, data_out);
        end else begin
            data_out = 32'd0;
        end
    end

endmodule

module \mem::Rom (
    input  wire     [31:0]  addr,
    output reg      [31:0]  instr
); /* verilator public_module */
    // 64KiB: 16384 entries * 4 bytes = 64 * 1024 bytes
    reg [31:0] mem[16384] /* verilator public */;

    always @(*) begin
        instr = mem[addr[15:2]];
    end
endmodule
