// SPI Flash Controller Testbench
// Sends wishbone requests to the SPI controller and dumps VCD to dump.vcd
// Run with: iverilog -g2012 -o spi_tb.vvp build/spi.sv spi_tb.sv && vvp spi_tb.vvp

module spi_tb;
    reg         clock;
    reg         reset;

    // Wishbone master interface
    reg         wb_cyc;
    reg         wb_stb;
    reg         wb_we;
    reg  [31:0] wb_adr;
    reg  [31:0] wb_dat_wr;
    reg   [3:0] wb_sel;
    wire        wb_ack;
    wire        wb_err;
    wire [31:0] wb_dat_rd;

    // SPI interface
    wire        spi_cs;
    wire        spi_clk;
    wire        spi_do;
    reg         spi_di;

    // SPI response generation for read commands
    reg  [31:0] spi_response_data;
    reg  [31:0] random_data;
    reg   [5:0] spi_edge_count;
    reg         spi_active;
    reg         spi_clk_d1;

    // Instantiate the Wishbone SPI flash controller
    // The module uses escaped identifiers (backslash notation)
    \spi::WbSpiFlash spi_ctrl (
        .clock      (clock),
        .reset      (reset),
        .\wb.cyc    (wb_cyc),
        .\wb.stb    (wb_stb),
        .\wb.we     (wb_we),
        .\wb.adr    (wb_adr),
        .\wb.dat_wr (wb_dat_wr),
        .\wb.sel    (wb_sel),
        .\wb.ack    (wb_ack),
        .\wb.err    (wb_err),
        .\wb.dat_rd (wb_dat_rd),
        .\spi.cs    (spi_cs),
        .\spi.clk   (spi_clk),
        .\spi.do    (spi_do),
        .\spi.di    (spi_di)
    );

    // Clock: 100 MHz period (10 ns half-cycle)
    always #5 clock = ~clock;

    // VCD dump to dump.vcd
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, spi_tb);
    end

    // Helper: issue a wishbone transaction
    task wb_transaction;
        input [31:0] address;
        input        write;    // 1 = write, 0 = read
        input [31:0] wdata;
        output [31:0] rdata;
        reg [31:0] rdata_reg;
        begin
            @(negedge clock);
            wb_cyc   <= 1;
            wb_stb   <= 1;
            wb_we    <= write;
            wb_adr   <= address;
            wb_dat_wr <= wdata;
            wb_sel   <= 4'b1111;

            // Wait for ack
            @(posedge clock);
            while (wb_ack !== 1'b1) begin
                @(posedge clock);
            end

            rdata_reg = wb_dat_rd;
            @(negedge clock);
            wb_cyc   <= 0;
            wb_stb   <= 0;
            wb_we    <= 0;
            wb_adr   <= 32'h0;
            wb_dat_wr <= 32'h0;
            wb_sel   <= 4'b0000;

            rdata = rdata_reg;
        end
    endtask

    // Test stimulus
    initial begin
        integer status;
        reg [31:0] readback;

        $display("========================================");
        $display("SPI Flash Controller Testbench");
        $display("========================================");

        // Initialize all signals
        clock    = 0;
        reset    = 1;
        wb_cyc   = 0;
        wb_stb   = 0;
        wb_we    = 0;
        wb_adr   = 32'h0;
        wb_dat_wr = 32'h0;
        wb_sel   = 4'b0000;
        spi_di   = 0;

        // Hold reset for 3 clock cycles
        repeat (3) @(posedge clock);
        reset = 0;
        $display("Released reset at t=%0t", $time);

        // =========================================================
        // Test 1: Write Enable (cmd_nib=1, we=1)
        // Address: 0x20010000 → adr[31:28]=2 (SPI), cmd_nib=1, addr=0
        // Sends opcode 0x06 (Write Enable) over SPI, no data phase
        // =========================================================
        $display("\n--- Test 1: Write Enable ---");
        wb_transaction(32'h2001_0000, 0, 32'h0, readback);
        $display("Write Enable complete at t=%0t", $time);

        // =========================================================
        // Test 2: Read Status Register (cmd_nib=1, we=0)
        // Sends opcode 0x05 (Read Status) over SPI, reads 8 bits back
        // Provide some dummy SPI data on spi_di during the read
        // =========================================================
        $display("\n--- Test 2: Read Status Register ---");
        // Drive spi_di with a pattern during the read phase
        fork
            begin
                // Wait for the status read phase (state 32 = 6'd32)
                // The SPI clock toggles; provide data on rising edges
                repeat (100) @(posedge clock);
            end
            begin
                wb_transaction(32'h2001_0000, 0, 32'h0, readback);
            end
        join
        $display("Status Register = %h at t=%0t", readback, $time);

        // =========================================================
        // Test 3: Page Program (Write data) - cmd_nib=2, we=1
        // Sends opcode 0x20 (Page Program), 24-bit address, then 32-bit data
        // Write value 0xAABBCCDD to SPI address 0x123456
        // =========================================================
        $display("\n--- Test 3: Page Program (Write Data) ---");
        // Need to write enable first
        wb_transaction(32'h2001_0000, 0, 32'h0, readback);
        $display("Write Enable done at t=%0t", $time);

        // Now page program: address = 0x2 | (cmd_nib=2 << 24) | 24-bit addr
        // 0x2000_0000 | 0x0200_0000 | 0x123456 = 0x2212_3456
        wb_transaction({4'h2, 4'h2, 24'h12_3456}, 0, 32'hAABB_CCDD, readback);
        $display("Page Program complete at t=%0t", $time);

        // =========================================================
        // Test 4: Read Data (cmd_nib=0, we=0 -> opcode 0x03)
        // The always block below monitors SPI and automatically drives
        // spi_di with a random 32-bit response during the readback phase.
        // =========================================================
        $display("\n--- Test 4: Read Data (cmd_nib=0, we=0) ---");
        wb_transaction({4'h2, 4'h0, 24'h12_3456}, 0, 32'h0, readback);
        $display("Read Data = %h at t=%0t", readback, $time);

        // =========================================================
        // Test 5: Sector Erase (cmd_nib=3, we=1)
        // Sends opcode 0xD8 (Sector Erase) over SPI
        // =========================================================
        $display("\n--- Test 5: Sector Erase ---");
        // Need to write enable first
        wb_transaction(32'h2001_0000, 0, 32'h0, readback);
        $display("Write Enable done at t=%0t", $time);

        // Erase sector at SPI address 0x000000
        wb_transaction({4'h2, 4'h3, 24'h0}, 0, 32'h0, readback);
        $display("Sector Erase complete at t=%0t", $time);

        // =========================================================
        // Done
        // =========================================================
        $display("\n========================================");
        $display("All tests complete at t=%0t", $time);
        $display("========================================");

        #200;
        $finish;
    end

    // SPI response generator: monitors SPI bus and drives spi_di
    // with a random 32-bit value during the readback phase.
    always @(posedge clock) begin
        spi_clk_d1 <= spi_clk;

        if (~spi_cs && ~spi_active) begin
            // Transaction started: CS just went low
            spi_active      <= 1;
            spi_edge_count  <= 0;
            spi_di          <= 0;
        end

        if (spi_active) begin
            // Detect rising edge of spi_clk
            if (spi_clk == 1 && spi_clk_d1 == 0) begin
                if (spi_edge_count < 31) begin
                    // Command + address output phase (0x03 + 24-bit addr = 32 bits)
                    // Edges 0..30 = first 31 output bits
                    spi_edge_count <= spi_edge_count + 1;
                end else if (spi_edge_count == 31) begin
                    // === Last OUTPUT edge (32nd output bit) ===
                    // Generate random response NOW so spi_di is settled
                    // by the next spi_clk edge (first INPUT edge).
                    // Non-blocking assignment of spi_di takes effect
                    // at end of this time step, before the controller
                    // samples it on the next posedge.
                    random_data = $random;
                    $display("SPI: Generated random response = %h at t=%0t", random_data, $time);
                    // First response bit (MSB) — ready for controller on next edge
                    spi_di <= random_data[31];
                    spi_response_data <= {random_data[30:0], 1'b0};
                    spi_edge_count <= spi_edge_count + 1;
                end else if (spi_edge_count < 63) begin
                    // Continue shifting in remaining bits MSB first
                    spi_di <= spi_response_data[31];
                    spi_response_data <= {spi_response_data[30:0], 1'b0};
                    spi_edge_count <= spi_edge_count + 1;
                end else begin
                    // Last bit (edge_count == 63)
                    spi_di <= spi_response_data[31];
                    spi_edge_count <= spi_edge_count + 1;
                end
            end
        end

        if (spi_cs) begin
            // Transaction ended
            spi_active <= 0;
            spi_di     <= 0;
        end
    end

    // Monitor progress
    initial begin
        $monitor("t=%0t: cs=%b clk=%b do=%b di=%b | cyc=%b stb=%b we=%b adr=%h ack=%b dat_rd=%h",
                 $time, spi_cs, spi_clk, spi_do, spi_di,
                 wb_cyc, wb_stb, wb_we, wb_adr, wb_ack, wb_dat_rd);
    end

    // Panic if wb_err is ever asserted
    always @(posedge clock) begin
        if (wb_err) begin
            $fatal(1, "PANIC: wb_err asserted at t=%0t (cyc=%b stb=%b we=%b)",
                   $time, wb_cyc, wb_stb, wb_we);
        end
    end

    // Timeout
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
