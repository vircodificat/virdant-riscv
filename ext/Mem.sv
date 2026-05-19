module \mem::Mem (
    input  wire             clock,
    input  wire     [31:0]  addr,
    input  wire     [31:0]  data_in,
    input  wire             write,
    output reg      [31:0]  data_out
);
    reg [31:0] mem[16384]; // 64KiB: 16384 entries * 4 bytes = 64 * 1024 bytes

    always @(*) begin
        data_out = mem[addr[15:2]];
    end

    always @(posedge clock) begin
        if (write) begin
            $display("Mem write: [0x%x] <= 0x%x", addr, data_in);
            mem[addr[15:2]] <= data_in;
        end
    end
endmodule

module \mem::Rom (
    input  wire     [31:0]  addr,
    output reg      [31:0]  instr
);
    reg [31:0] mem[16384]; // 64KiB: 16384 entries * 4 bytes = 64 * 1024 bytes

    always @(*) begin
        instr = mem[addr[15:2]];
    end

    initial begin
        string rom_hex;
        $value$plusargs("rom_hex=%s", rom_hex);
        $readmemh(rom_hex, mem);
    end
endmodule
