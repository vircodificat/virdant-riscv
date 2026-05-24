// UART Transmitter & Receiver Testbench
// Connects UartSender to UartReceiver in loopback, sends test bytes,
// and verifies correct reception. Dumps VCD to uart_dump.vcd
// Run with: iverilog -g2012 -o uart_tb.vvp build/uart.sv uart_tb.sv && vvp uart_tb.vvp

module uart_tb;
    reg         clock;
    reg         reset;

    // UartSender interface
    reg  [7:0]  tx_data;
    reg         tx_data_valid;
    wire        tx_ready;
    wire        uart_tx;

    // UartReceiver interface
    wire [7:0]  rx_data;
    wire        rx_data_valid;
    reg         uart_rx;

    // Instantiate UartSender
    \uart::UartSender sender (
        .clock      (clock),
        .reset      (reset),
        .data       (tx_data),
        .data_valid (tx_data_valid),
        .ready      (tx_ready),
        .uart_tx    (uart_tx)
    );

    // Instantiate UartReceiver
    \uart::UartReceiver receiver (
        .clock      (clock),
        .reset      (reset),
        .uart_rx    (uart_rx),
        .data       (rx_data),
        .data_valid (rx_data_valid)
    );

    // Clock: 100 MHz (10 ns half-cycle)
    always #5 clock = ~clock;

    // VCD dump to uart_dump.vcd
    initial begin
        $dumpfile("uart_dump.vcd");
        $dumpvars(0, uart_tb);
    end

    // Loopback: connect sender serial output directly to receiver serial input
    always @* uart_rx = uart_tx;

    // Helper: wait for N posedge clock cycles
    task wait_cycles;
        input integer n;
        begin
            repeat (n) @(posedge clock);
        end
    endtask

    // Helper: load a byte into the UartSender (non-blocking, returns immediately)
    task uart_send_byte;
        input [7:0] byte_val;
        begin
            @(negedge clock);
            tx_data       <= byte_val;
            tx_data_valid <= 1;
            @(negedge clock);
            tx_data_valid <= 0;
        end
    endtask

    // Helper: wait for rx_data_valid and check the received byte (with timeout)
    task uart_check_receive;
        input [7:0] expected;
        output      match;
        begin
            match = 0;
            fork
                begin: waiter
                    @(posedge rx_data_valid);
                    if (rx_data === expected) begin
                        $display("  Received 0x%02h correctly at t=%0t", rx_data, $time);
                        match = 1;
                    end else begin
                        $display("  MISMATCH: expected 0x%02h, got 0x%02h at t=%0t",
                                 expected, rx_data, $time);
                    end
                end
                begin: timeout
                    wait_cycles(25000);
                    $display("  TIMEOUT waiting for 0x%02h at t=%0t", expected, $time);
                end
            join_any
            disable fork;
        end
    endtask

    // Helper: send byte and verify reception — handles the fact that the
    // receiver's data_valid strobe fires *before* the sender's ready goes
    // high (receiver samples the stop bit edge faster than the sender
    // finishes its stop bit countdown).
    task uart_send_and_check;
        input [7:0] byte_val;
        output      pass;
        begin
            pass = 0;
            $display("  Sending 0x%02h ...", byte_val);
            // 1) Start the byte transmission (non-blocking)
            uart_send_byte(byte_val);
            // 2) Wait for receiver output or timeout
            uart_check_receive(byte_val, pass);
            // 3) Wait for sender to be ready again before next test
            @(posedge tx_ready);
            $display("  Sender ready for next byte at t=%0t", $time);
        end
    endtask

    // Test stimulus
    initial begin
        integer pass_count;
        integer fail_count;
        reg      ok;

        pass_count = 0;
        fail_count = 0;

        $display("========================================");
        $display("UART Transmitter & Receiver Testbench");
        $display("========================================");
        $display("Clock: 100 MHz (10 ns half-cycle)");
        $display("Baud rate divisor: 1250 (~80 kbaud in sim)");
        $display("Loopback: sender.uart_tx -> receiver.uart_rx");
        $display("========================================\n");

        // Initialize all signals
        clock         = 0;
        reset         = 1;
        tx_data       = 8'h00;
        tx_data_valid = 0;
        uart_rx       = 1;  // idle high

        // Hold reset for 3 clock cycles
        wait_cycles(3);
        reset = 0;
        $display("Released reset at t=%0t", $time);

        // Verify sender is ready after reset
        wait_cycles(5);
        if (tx_ready !== 1'b1) begin
            $display("FATAL: Sender not ready after reset at t=%0t", $time);
            $finish;
        end
        $display("Sender ready at t=%0t\n", $time);

        // =========================================================
        // Test 1: Alternating bits (0x55)
        //  Serial: start(0) 1 0 1 0 1 0 1 0 stop(1)
        // =========================================================
        $display("--- Test 1: Byte 0x55 (alternating 01010101) ---");
        uart_send_and_check(8'h55, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 2: Reverse alternating (0xAA)
        //  Serial: start(0) 0 1 0 1 0 1 0 1 stop(1)
        // =========================================================
        $display("--- Test 2: Byte 0xAA (alternating 10101010) ---");
        uart_send_and_check(8'hAA, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 3: All zeros (0x00)
        // =========================================================
        $display("--- Test 3: Byte 0x00 (all zeros) ---");
        uart_send_and_check(8'h00, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 4: All ones (0xFF)
        // =========================================================
        $display("--- Test 4: Byte 0xFF (all ones) ---");
        uart_send_and_check(8'hFF, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 5: ASCII 'A' (0x41)
        // =========================================================
        $display("--- Test 5: Byte 0x41 (ASCII 'A') ---");
        uart_send_and_check(8'h41, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 6: ASCII 'Z' (0x5A)
        // =========================================================
        $display("--- Test 6: Byte 0x5A (ASCII 'Z') ---");
        uart_send_and_check(8'h5A, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Test 7-10: Ramp pattern bytes
        // =========================================================
        $display("--- Test 7: Byte 0x12 ---");
        uart_send_and_check(8'h12, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        $display("--- Test 8: Byte 0x34 ---");
        uart_send_and_check(8'h34, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        $display("--- Test 9: Byte 0x56 ---");
        uart_send_and_check(8'h56, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        $display("--- Test 10: Byte 0x78 ---");
        uart_send_and_check(8'h78, ok);
        if (ok) pass_count = pass_count + 1;
        else    fail_count = fail_count + 1;

        // =========================================================
        // Summary
        // =========================================================
        $display("\n========================================");
        $display("  Tests passed: %0d / 10", pass_count);
        $display("  Tests failed: %0d / 10", fail_count);
        if (fail_count == 0) begin
            $display("  RESULT: ALL TESTS PASSED");
        end else begin
            $display("  RESULT: SOME TESTS FAILED");
        end
        $display("========================================");

        #500;
        $finish;
    end

    // Monitor progress
    initial begin
        $monitor("t=%0t: tx_ready=%b uart_tx=%b | rx_data_valid=%b rx_data=0x%02h",
                 $time, tx_ready, uart_tx, rx_data_valid, rx_data);
    end

    // Timeout: 5 milliseconds prevents hanging on bugs
    initial begin
        #5_000_000;
        $display("FATAL: Testbench timeout at t=%0t", $time);
        $finish;
    end

endmodule
