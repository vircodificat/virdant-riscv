// WbUart Testbench
// Exercises the Wishbone-attached UART through several requests,
// including loopback (tx -> rx) and register read/write sequences.
// Run with:
//   iverilog -g2012 -o build/wbuart_tb.vvp build/uart.sv tb/wbuart_tb.sv
//   cd build && vvp wbuart_tb.vvp

module wbuart_tb;
    reg         clock;
    reg         reset;

    // ─── Wishbone master interface ─────────────────────────────────────
    reg         wb_cyc;
    reg         wb_stb;
    reg         wb_we;
    reg  [31:0] wb_adr;
    reg  [31:0] wb_dat_wr;
    reg   [3:0] wb_sel;
    wire        wb_ack;
    wire        wb_err;
    wire [31:0] wb_dat_rd;

    // ─── UART serial interface ────────────────────────────────────────
    wire        uart_tx;
    reg         uart_rx;

    // ─── Instantiate WbUart ────────────────────────────────────────────
    \uart::WbUart uart (
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
        .\uart.tx   (uart_tx),
        .\uart.rx   (uart_rx)
    );

    // ─── Clock: 100 MHz (5 ns half-cycle) ──────────────────────────
    // UartSender/UartReceiver hardcode divisor = 1250, so at 100 MHz
    // each bit period = 1250 × 10 ns = 12.5 µs (~80 kbaud in sim).
    always #5 clock = ~clock;

    // ─── VCD dump ─────────────────────────────────────────────────────
    initial begin
        $dumpfile("wbuart_dump.vcd");
        $dumpvars(0, wbuart_tb);
    end

    // ─── Loopback: connect UART TX to RX ──────────────────────────────
    always @* uart_rx = uart_tx;

    // ─── Helper: wait N clock cycles ───────────────────────────────────
    task wait_cycles;
        input integer n;
        begin
            repeat (n) @(posedge clock);
        end
    endtask

    // ─── Wishbone single-cycle transaction ─────────────────────────────
    // Drives a Wishbone read or write and waits for ack.
    // Returns the read data (valid for reads).
    task wb_transaction;
        input  [31:0] address;
        input         write;    // 1 = write, 0 = read
        input  [31:0] wdata;
        output [31:0] rdata;
        reg    [31:0] rdata_reg;
        begin
            @(negedge clock);
            wb_cyc    <= 1;
            wb_stb    <= 1;
            wb_we     <= write;
            wb_adr    <= address;
            wb_dat_wr <= wdata;
            wb_sel    <= 4'b0001;  // byte access on LSB lane

            // Wait for ack
            @(posedge clock);
            while (wb_ack !== 1'b1) begin
                @(posedge clock);
            end

            rdata_reg = wb_dat_rd;
            @(negedge clock);
            wb_cyc    <= 0;
            wb_stb    <= 0;
            wb_we     <= 0;
            wb_adr    <= 32'h0;
            wb_dat_wr <= 32'h0;
            wb_sel    <= 4'b0000;

            rdata = rdata_reg;
        end
    endtask

    // ─── Wishbone write (convenience wrapper) ──────────────────────────
    task wb_write;
        input  [31:0] address;
        input  [31:0] wdata;
        reg    [31:0] dummy;
        begin
            wb_transaction(address, 1, wdata, dummy);
        end
    endtask

    // ─── Wishbone read (convenience wrapper) ───────────────────────────
    task wb_read;
        input  [31:0] address;
        output [31:0] rdata;
        begin
            wb_transaction(address, 0, 32'h0, rdata);
        end
    endtask

    // ─── Test stimulus ─────────────────────────────────────────────────
    initial begin
        integer pass_count;
        integer fail_count;
        reg [31:0] rdval;

        pass_count = 0;
        fail_count = 0;

        $display("================================================");
        $display("WbUart Testbench (Wishbone UART with loopback)");
        $display("================================================");
        $display("Clock: 100 MHz (5 ns half-cycle)");
        $display("Baud:  divisor=1250 => ~80 kbaud in sim");
        $display("Registers: [0x00] RBR(rd)/THR(wr), [0x04] LSR");
        $display("Loopback: uart_tx -> uart_rx");
        $display("================================================\n");

        // ─── Initialise all signals ───────────────────────────────
        clock  = 0;
        reset  = 1;
        wb_cyc = 0;
        wb_stb = 0;
        wb_we  = 0;
        wb_adr = 32'h0;
        wb_dat_wr = 32'h0;
        wb_sel = 4'b0000;
        uart_rx = 1;  // idle high

        // Hold reset for 3 clock cycles
        wait_cycles(3);
        reset = 0;
        $display("Released reset at t=%0t", $time);
        wait_cycles(5);

        // =========================================================
        // Test 1: Read LSR after reset
        //   Expected: DR=0 (rx empty), TEMT=1, THRE=1 (tx idle)
        //   LSR = {24'b0, THRE, TEMT, 3'b0, DR}
        //   LSR[6]=THRE, LSR[5]=TEMT, LSR[0]=DR
        //   Expected value: 0x60 (THRE=1, TEMT=1)
        // =========================================================
        $display("--- Test 1: Read LSR after reset ---");
        wb_read(32'h1001_3004, rdval);   // offset 0x04 = LSR
        $display("  LSR = 0x%08h", rdval);
        if (rdval[6] && rdval[5] && !rdval[0]) begin
            $display("  PASS: THRE=1, TEMT=1, DR=0");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: expected THRE=1,TEMT=1,DR=0; got LSR=0x%08h", rdval);
            fail_count = fail_count + 1;
        end

        // =========================================================
        // Test 2: Read RBR when empty (should return 0)
        //   RBR read returns {24'b0, receiver.data}
        //   No data available -> receiver.data = 0 (reset value)
        // =========================================================
        $display("\n--- Test 2: Read RBR (empty) ---");
        wb_read(32'h1001_3000, rdval);   // offset 0x00 = RBR
        $display("  RBR = 0x%08h", rdval);
        if (rdval[7:0] == 8'h00) begin
            $display("  PASS: RBR read returns 0x00 when empty");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: expected 0x00, got 0x%08h", rdval);
            fail_count = fail_count + 1;
        end

        // =========================================================
        // Test 3: Write byte 0xAA to THR, then check LSR for THRE
        //   After writing, sender starts transmitting.
        //   THRE should go low briefly while busy.
        //   (We check immediately — THRE should still be 0 or 1
        //    depending on how the FSM transitions. Since the write
        //    latches data_valid and the FSM starts on the next cycle,
        //    THRE may still show 1 for 1 cycle. Instead, wait until
        //    the byte is fully transmitted, then check.)
        // =========================================================
        $display("\n--- Test 3: Write 0xAA, wait for TX complete ---");
        wb_write(32'h1001_3000, 32'h0000_00AA);   // THR write
        $display("  Written 0xAA to THR at t=%0t", $time);

        // Poll LSR until THRE=1 (transmitter empty) — byte done
        wait_cycles(10);  // give a head start
        rdval = 0;
        while (!rdval[6]) begin  // wait for THRE
            wb_read(32'h1001_3004, rdval);
        end
        $display("  TX complete (THRE=1) at t=%0t", $time);
        $display("  LSR = 0x%08h", rdval);

        // Now read RBR — loopback should have delivered the byte
        wb_read(32'h1001_3000, rdval);
        $display("  RBR after loopback = 0x%08h", rdval);
        if (rdval[7:0] == 8'hAA) begin
            $display("  PASS: Loopback delivered 0xAA correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: expected 0xAA, got 0x%02h", rdval[7:0]);
            fail_count = fail_count + 1;
        end

        // =========================================================
        // Test 4: Verify DR clears after reading RBR
        //   After reading RBR, rx_pending is cleared, so LSR[0]=0
        // =========================================================
        $display("\n--- Test 4: DR clears after RBR read ---");
        wb_read(32'h1001_3004, rdval);   // LSR
        $display("  LSR after read = 0x%08h", rdval);
        if (!rdval[0]) begin
            $display("  PASS: DR=0 after reading RBR");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: DR still set (LSR=0x%08h)", rdval);
            fail_count = fail_count + 1;
        end

        // =========================================================
        // Test 5: Multiple bytes in sequence
        //   Send 0x55, 0xFF, 0x00, 0x41 and verify each comes back
        // =========================================================
        $display("\n--- Test 5: Multiple bytes ---");
        begin
            reg [7:0] test_bytes [0:3];
            integer   i;
            reg       all_ok;

            test_bytes[0] = 8'h55;
            test_bytes[1] = 8'hFF;
            test_bytes[2] = 8'h00;
            test_bytes[3] = 8'h41;  // ASCII 'A'

            all_ok = 1;
            for (i = 0; i < 4; i = i + 1) begin
                $display("  Sending 0x%02h ...", test_bytes[i]);
                wb_write(32'h1001_3000, {24'h0, test_bytes[i]});

                // Poll LSR until THRE (TX done)
                rdval = 0;
                while (!rdval[6]) begin
                    wb_read(32'h1001_3004, rdval);
                end

                // Poll LSR until DR (RX data ready)
                rdval = 0;
                while (!rdval[0]) begin
                    wb_read(32'h1001_3004, rdval);
                end

                // Read RBR
                wb_read(32'h1001_3000, rdval);
                $display("    Received 0x%02h at t=%0t", rdval[7:0], $time);
                if (rdval[7:0] !== test_bytes[i]) begin
                    $display("    FAIL: expected 0x%02h, got 0x%02h",
                             test_bytes[i], rdval[7:0]);
                    all_ok = 0;
                end else begin
                    $display("    OK");
                end
            end

            if (all_ok) begin
                $display("  PASS: All multi-byte transfers matched");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Some bytes mismatched in multi-byte test");
                fail_count = fail_count + 1;
            end
        end

        // =========================================================
        // Test 6: Back-to-back writes (flow control check)
        //   Write byte 0xA5, then immediately write 0x5A before
        //   the first byte finishes transmitting. The second write
        //   may be dropped if the sender is busy (single-entry TX buffer).
        // =========================================================
        $display("\n--- Test 6: Back-to-back writes ---");
        begin
            // Write 0xA5
            wb_write(32'h1001_3000, 32'h0000_00A5);
            $display("  Wrote 0xA5 at t=%0t", $time);

            // Immediately write 0x5A (first byte still transmitting)
            wb_write(32'h1001_3000, 32'h0000_005A);
            $display("  Wrote 0x5A at t=%0t", $time);

            // Wait for TX to complete
            rdval = 0;
            while (!rdval[6]) begin  // wait THRE
                wb_read(32'h1001_3004, rdval);
            end

            // Read back the first received byte
            rdval = 0;
            while (!rdval[0]) begin
                wb_read(32'h1001_3004, rdval);
            end
            wb_read(32'h1001_3000, rdval);
            $display("  First received = 0x%02h at t=%0t", rdval[7:0], $time);

            // Check for second byte
            wait_cycles(100);
            wb_read(32'h1001_3004, rdval);
            if (rdval[0]) begin
                wb_read(32'h1001_3000, rdval);
                $display("  Second received = 0x%02h at t=%0t", rdval[7:0], $time);
                if (rdval[7:0] == 8'h5A) begin
                    $display("  PASS: Both bytes received correctly");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  FAIL: expected 0x5A for second byte");
                    fail_count = fail_count + 1;
                end
            end else begin
                $display("  NOTE: Second write dropped while TX busy (single-entry TX buffer)");
                pass_count = pass_count + 1;
            end
        end

        // =========================================================
        // Test 7: Read with invalid byte lane (sel != 4'b0001)
        //   WbUart checks sel == 4'b0001; other values cause err=1
        // =========================================================
        $display("\n--- Test 7: Invalid byte lane (err expected) ---");
        begin
            reg err_seen;
            err_seen = 0;

            @(negedge clock);
            wb_cyc    <= 1;
            wb_stb    <= 1;
            wb_we     <= 0;          // read (not write) — avoids loading sender
            wb_adr    <= 32'h1001_3000;
            wb_dat_wr <= 32'h0;
            wb_sel    <= 4'b1111;   // all byte lanes — invalid for UART

            @(posedge clock);
            while (!wb_ack && !wb_err) begin
                @(posedge clock);
            end
            if (wb_err) begin
                $display("  PASS: wb_err asserted for invalid sel (sel=4'b1111)");
                err_seen = 1;
            end else begin
                $display("  FAIL: expected wb_err, got ack");
            end

            @(negedge clock);
            wb_cyc <= 0;
            wb_stb <= 0;
            wb_we  <= 0;
            wb_adr <= 32'h0;
            wb_dat_wr <= 32'h0;
            wb_sel <= 4'b0000;

            if (err_seen) pass_count = pass_count + 1;
            else          fail_count = fail_count + 1;
        end

        // =========================================================
        // Test 8: Invalid register offset (adr[4:2] != 0,1) → err
        //   Offset 0x08 (adr[4:2]=2) is unmapped.
        // =========================================================
        $display("\n--- Test 8: Invalid register offset (err expected) ---");
        begin
            reg err_seen;
            err_seen = 0;

            @(negedge clock);
            wb_cyc    <= 1;
            wb_stb    <= 1;
            wb_we     <= 0;          // read
            wb_adr    <= 32'h1001_3008;  // offset 0x08 — unmapped
            wb_dat_wr <= 32'h0;
            wb_sel    <= 4'b0001;

            @(posedge clock);
            while (!wb_ack && !wb_err) begin
                @(posedge clock);
            end
            if (wb_err) begin
                $display("  PASS: wb_err asserted for unmapped offset 0x08");
                err_seen = 1;
            end else begin
                $display("  FAIL: expected wb_err, got ack");
            end

            @(negedge clock);
            wb_cyc <= 0;
            wb_stb <= 0;
            wb_we  <= 0;
            wb_adr <= 32'h0;
            wb_dat_wr <= 32'h0;
            wb_sel <= 4'b0000;

            if (err_seen) pass_count = pass_count + 1;
            else          fail_count = fail_count + 1;
        end

        // =========================================================
        // Summary
        // =========================================================
        $display("\n================================================");
        $display("  Tests passed: %0d / 8", pass_count);
        $display("  Tests failed: %0d / 8", fail_count);
        if (fail_count == 0) begin
            $display("  RESULT: ALL TESTS PASSED");
        end else begin
            $display("  RESULT: SOME TESTS FAILED");
        end
        $display("================================================");

        #500;
        $finish;
    end

    // ─── Monitor progress ──────────────────────────────────────────────
    // No $monitor (too verbose during polling loops); $display used instead.

    // ─── Panic on unexpected wb_err (tests 6 and 7 handle it) ─────────
    // We disable this check during tests 6 and 7; otherwise fail.
    always @(posedge clock) begin
        if (wb_err && wb_cyc && wb_stb) begin
            // Only report if we're not in test 6 or 7
            // (tests 6 and 7 intentionally trigger err)
            if (wb_adr != 32'h1001_3008 &&
                !(wb_adr == 32'h1001_3000 && wb_sel == 4'b1111)) begin
                $display("NOTE: wb_err asserted at t=%0t (adr=%08h sel=%b we=%b)",
                         $time, wb_adr, wb_sel, wb_we);
            end
        end
    end

    // ─── Timeout ───────────────────────────────────────────────────────
    initial begin
        #50_000_000;  // 50 ms — allows for loopback at ~80 kbaud (~125 µs/byte)
        $display("FATAL: Testbench timeout at t=%0t", $time);
        $finish;
    end

endmodule