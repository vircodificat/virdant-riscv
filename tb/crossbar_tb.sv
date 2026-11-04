// Wishbone crossbar (WbCrossbar23) testbench.
//
// Models the real SoC traffic that exposed the dropped-store bug:
//   - client_0 behaves like the CPU: instruction fetch from SPI flash
//     (slow ack), then -- with cyc still held -- a store to RAM, then a
//     load back from RAM.
//   - client_1 (the ErrorReport master) is normally idle, but a
//     contention test drives it against client_0 on the RAM port.
//   - server stubs match the real slaves' ack timing:
//       SPI  : acks after SPI_LATENCY strobe cycles (slow, registered)
//       UART : acks combinationally (same cycle as strobe)
//       RAM  : acks combinationally (same cycle as strobe)
//
// Ack timing is measured with edge-qualified probes (ack && strobe,
// sampled #1 after each posedge so the NBA update has settled).
// `lat` counts strobe cycles held until ack: 1 = same-cycle ack
// (combinational slave), 2 = one registered-grant wait state, etc.
//
// Tests 7..13 (added in round 2): parallel clients on distinct servers,
// byte-lane sel handling, slave err propagation, sustained-contention
// fairness, unmapped-address decode, mid-transaction grant switch
// (phantom-strobe / stale-ack gating), and request re-target while
// queued behind another master.
//
// Run with:
//   iverilog -g2012 -o build/crossbar_tb.vvp build/wishbone.sv tb/crossbar_tb.sv
//   vvp build/crossbar_tb.vvp

`timescale 1ns/1ps

module crossbar_tb;
    reg clock;
    reg reset;

    // client_0 (CPU-like master)
    reg          c0_cyc;
    reg          c0_stb;
    reg          c0_we;
    reg  [31:0]  c0_adr;
    reg  [31:0]  c0_dat_wr;
    reg  [3:0]   c0_sel;
    wire         c0_ack;
    wire         c0_err;
    wire [31:0]  c0_dat_rd;

    // client_1 (ErrorReport-like master)
    reg          c1_cyc;
    reg          c1_stb;
    reg          c1_we;
    reg  [31:0]  c1_adr;
    reg  [31:0]  c1_dat_wr;
    reg  [3:0]   c1_sel;
    wire         c1_ack;
    wire         c1_err;
    wire [31:0]  c1_dat_rd;

    // SPI flash stub (server_0)
    wire        s0_cyc, s0_stb, s0_we;
    wire [31:0] s0_adr, s0_dat_wr;
    wire [3:0]  s0_sel;
    reg         s0_ack;
    wire        s0_err = 1'b0;
    wire [31:0] s0_dat_rd;
    assign s0_dat_rd = 32'h12340000 + s0_adr[7:0];

    // UART stub (server_1): combinational ack
    wire        s1_cyc, s1_stb, s1_we;
    wire [31:0] s1_adr, s1_dat_wr;
    wire [3:0]  s1_sel;
    wire        s1_ack;
    wire        s1_err = 1'b0;
    wire [31:0] s1_dat_rd = 32'h00000060;   // LSR: THRE|TEMT
    assign s1_ack = s1_cyc && s1_stb;

    // RAM stub (server_2): combinational ack, byte-lane writes
    wire        s2_cyc, s2_stb, s2_we;
    wire [31:0] s2_adr, s2_dat_wr;
    wire [3:0]  s2_sel;
    wire        s2_ack;
    reg         s2_err_r;               // TB-forced slave error (test 9)
    wire        s2_err;
    wire [31:0] s2_dat_rd;
    reg  [31:0] ram [0:255];
    assign s2_ack = s2_cyc && s2_stb && !s2_err_r;
    assign s2_err = s2_err_r && s2_cyc && s2_stb;
    assign s2_dat_rd = ram[s2_adr[9:2]];

    localparam SPI_LATENCY = 10;

    \wishbone::WbCrossbar23 dut (
        .clock          (clock),
        .reset          (reset),
        .\server_0.cyc    (s0_cyc),
        .\server_0.stb    (s0_stb),
        .\server_0.we     (s0_we),
        .\server_0.adr    (s0_adr),
        .\server_0.dat_wr (s0_dat_wr),
        .\server_0.sel    (s0_sel),
        .\server_0.ack    (s0_ack),
        .\server_0.err    (s0_err),
        .\server_0.dat_rd (s0_dat_rd),
        .\server_1.cyc    (s1_cyc),
        .\server_1.stb    (s1_stb),
        .\server_1.we     (s1_we),
        .\server_1.adr    (s1_adr),
        .\server_1.dat_wr (s1_dat_wr),
        .\server_1.sel    (s1_sel),
        .\server_1.ack    (s1_ack),
        .\server_1.err    (s1_err),
        .\server_1.dat_rd (s1_dat_rd),
        .\server_2.cyc    (s2_cyc),
        .\server_2.stb    (s2_stb),
        .\server_2.we     (s2_we),
        .\server_2.adr    (s2_adr),
        .\server_2.dat_wr (s2_dat_wr),
        .\server_2.sel    (s2_sel),
        .\server_2.ack    (s2_ack),
        .\server_2.err    (s2_err),
        .\server_2.dat_rd (s2_dat_rd),
        .\client_0.cyc    (c0_cyc),
        .\client_0.stb    (c0_stb),
        .\client_0.we     (c0_we),
        .\client_0.adr    (c0_adr),
        .\client_0.dat_wr (c0_dat_wr),
        .\client_0.sel    (c0_sel),
        .\client_0.ack    (c0_ack),
        .\client_0.err    (c0_err),
        .\client_0.dat_rd (c0_dat_rd),
        .\client_1.cyc    (c1_cyc),
        .\client_1.stb    (c1_stb),
        .\client_1.we     (c1_we),
        .\client_1.adr    (c1_adr),
        .\client_1.dat_wr (c1_dat_wr),
        .\client_1.sel    (c1_sel),
        .\client_1.ack    (c1_ack),
        .\client_1.err    (c1_err),
        .\client_1.dat_rd (c1_dat_rd)
    );

    always #5 clock = ~clock;

    // ── SPI stub: acks after SPI_LATENCY strobe cycles ────────────────
    reg [7:0] s0_wait;
    always @(posedge clock) begin
        if (reset) begin
            s0_wait <= 0;
            s0_ack  <= 0;
        end else if (s0_ack) begin
            s0_ack <= 0;               // one-cycle ack pulse
        end else if (s0_cyc && s0_stb) begin
            if (s0_wait == SPI_LATENCY) begin
                s0_ack  <= 1;
                s0_wait <= 0;
            end else begin
                s0_wait <= s0_wait + 1;
            end
        end
    end

    // ── RAM stub: byte-lane writes on strobe ──────────────────────────
    always @(posedge clock) begin
        if (s2_cyc && s2_stb && s2_we) begin
            if (s2_sel[0]) ram[s2_adr[9:2]][7:0]   <= s2_dat_wr[7:0];
            if (s2_sel[1]) ram[s2_adr[9:2]][15:8]  <= s2_dat_wr[15:8];
            if (s2_sel[2]) ram[s2_adr[9:2]][23:16] <= s2_dat_wr[23:16];
            if (s2_sel[3]) ram[s2_adr[9:2]][31:24] <= s2_dat_wr[31:24];
        end
    end

    // ── Edge-qualified ack probes ─────────────────────────────────────
    // ack0_evt is 1 iff client_0.ack was high during the cycle that just
    // ended while its strobe was asserted.  Normalizes X (dontcare grant
    // while idle) to 0.  Harness reads it #1 after each posedge.
    reg ack0_evt, ack1_evt;
    always @(posedge clock) begin
        ack0_evt <= (c0_ack === 1'b1) && (c0_stb === 1'b1);
        ack1_evt <= (c1_ack === 1'b1) && (c1_stb === 1'b1);
    end

    // ── Cycle tracing (first 80 cycles) ───────────────────────────────
    integer trace_cycles;
    always @(posedge clock) begin
        if (trace_cycles < 80) begin
            trace_cycles = trace_cycles + 1;
            $display("cyc %0d: c0: cyc=%b stb=%b we=%b adr=%h | s0: cyc=%b stb=%b ack=%b | s2: cyc=%b stb=%b ack=%b | c0_ack=%b c1_ack=%b",
                     trace_cycles, c0_cyc, c0_stb, c0_we, c0_adr,
                     s0_cyc, s0_stb, s0_ack, s2_cyc, s2_stb, s2_ack,
                     c0_ack, c1_ack);
        end
    end

    // ── Test scaffolding ──────────────────────────────────────────────
    integer errors;
    integer lat;
    integer acks0, acks1;               // test 10 ack counters
    reg [31:0] d0, d1;                  // read data captured at ack time
    reg s0_acked;                       // sticky: SPI stub ever acked

    always @(posedge clock) begin
        if (s0_ack) s0_acked <= 1'b1;
    end

    task fail(input [8*64:1] name);
        begin
            errors = errors + 1;
            $display("FAIL: %0s", name);
        end
    endtask

    task pass(input [8*64:1] name);
        begin
            $display("pass: %0s", name);
        end
    endtask

    // Complete one client_0 transaction.  Strobe must already be asserted
    // (call at #1 after a posedge).  Clears the ack probe (killing any
    // stale ack from the previous transaction), then waits, checking the
    // probe #1 after each posedge.  Drops stb as soon as ack is seen.
    // lat = strobe cycles held until ack (1 = same-cycle ack).
    task run_c0_until_ack;
        integer n;
        reg done;
        begin
            ack0_evt = 0;
            done = 0;
            n = 0;
            while (!done && n < 100) begin
                @(posedge clock);
                n = n + 1;
                #1;
                if (ack0_evt === 1'b1) done = 1;
            end
            lat = n;
            c0_stb = 0;
            if (!done) fail("client_0 ack timeout");
        end
    endtask

    // Same for client_1.
    task run_c1_until_ack;
        integer n;
        reg done;
        begin
            ack1_evt = 0;
            done = 0;
            n = 0;
            while (!done && n < 100) begin
                @(posedge clock);
                n = n + 1;
                #1;
                if (ack1_evt === 1'b1) done = 1;
            end
            c1_stb = 0;
            if (!done) fail("client_1 ack timeout");
        end
    endtask

    initial begin
        errors = 0;
        clock = 0;
        reset = 1;
        c0_cyc = 0; c0_stb = 0; c0_we = 0; c0_adr = 0; c0_dat_wr = 0; c0_sel = 0;
        c1_cyc = 0; c1_stb = 0; c1_we = 0; c1_adr = 0; c1_dat_wr = 0; c1_sel = 0;
        s0_ack = 0;
        s2_err_r = 0;
        ack0_evt = 0;
        ack1_evt = 0;
        trace_cycles = 0;
        #1;
        repeat (3) @(posedge clock);
        #1 reset = 0;
        @(posedge clock); #1;

        // ── Test 1: fetch from SPI (0x20000000) ──────────────────────
        // Registered grant: request cycle 0, grant latches at edge 1,
        // SPI stub then counts SPI_LATENCY strobe cycles, ack pulses the
        // cycle after the counter saturates.
        c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_adr = 32'h2000_0000; c0_sel = 4'hF;
        run_c0_until_ack;
        $display("  fetch ack latency: %0d strobe cycles", lat);
        if (lat == SPI_LATENCY + 3) pass("fetch ack latency (grant+SPI_LATENCY+1)");
        else fail("fetch ack latency (grant+SPI_LATENCY+1)");

        // ── Test 2: immediately store to RAM (cyc held, like the CPU) ─
        // The exact sequence that dropped stores.
        c0_cyc = 1; c0_stb = 1; c0_we = 1;
        c0_adr = 32'h8000_0000; c0_dat_wr = 32'hDEAD_BEEF; c0_sel = 4'hF;
        run_c0_until_ack;
        $display("  store-to-RAM ack latency: %0d strobe cycles", lat);
        if (ram[0] === 32'hDEAD_BEEF) pass("store to RAM written (ram[0]==DEADBEEF)");
        else fail("store to RAM written (ram[0]==DEADBEEF)");
        if (lat == 2) pass("registered-grant RAM store takes 2 strobe cycles");
        else if (lat == 1) pass("combinational RAM store takes 1 strobe cycle");
        else fail("RAM store latency (want 1 or 2)");
        c0_cyc = 0;

        // ── Test 3: load back from RAM ───────────────────────────────
        c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_adr = 32'h8000_0000; c0_sel = 4'hF;
        run_c0_until_ack;
        $display("  load-from-RAM ack latency: %0d strobe cycles", lat);
        if (c0_dat_rd === 32'hDEAD_BEEF) pass("load returns stored word");
        else fail("load returns stored word");
        c0_cyc = 0;

        // ── Test 4: store to UART ─────────────────────────────────────
        // UART slave acks combinationally, but the registered grant adds
        // one wait state, same as RAM.
        c0_cyc = 1; c0_stb = 1; c0_we = 1;
        c0_adr = 32'h4000_0000; c0_dat_wr = 32'h0000_0041; c0_sel = 4'h1;
        run_c0_until_ack;
        $display("  store-to-UART ack latency: %0d strobe cycles", lat);
        if (lat == 2) pass("UART store acks in 2 strobe cycles (registered grant)");
        else fail("UART store acks in 2 strobe cycles (registered grant)");
        c0_cyc = 0;

        // ── Test 5: contention — both clients hit RAM same cycle ─────
        // c1 wins the first grant (like the real ErrorReport master: one
        // shot, then idle).  As soon as c1 acks, drop its strobe so the
        // arbiter re-grants the port to c0 and c0's store completes.
        c0_cyc = 1; c0_stb = 1; c0_we = 1;
        c0_adr = 32'h8000_0004; c0_dat_wr = 32'hAAAA_0001; c0_sel = 4'hF;
        c1_cyc = 1; c1_stb = 1; c1_we = 1;
        c1_adr = 32'h8000_0008; c1_dat_wr = 32'hBBBB_0002; c1_sel = 4'hF;
        ack1_evt = 0;
        begin
            integer n;
            n = 0;
            while (!ack1_evt && n < 100) begin
                @(posedge clock); #1; n = n + 1;
            end
            if (ack1_evt) pass("contended c1 store acks (granted first)");
            else fail("c1 ack timeout under contention");
            c1_stb = 0;
        end
        run_c0_until_ack;
        $display("  contended c0 store ack latency: %0d strobe cycles", lat);
        if (lat < 20) pass("contended c0 store acks (serialized)");
        else fail("contended c0 store acks (serialized)");
        c0_cyc = 0; c1_cyc = 0;
        @(posedge clock); #1;
        if (ram[1] === 32'hAAAA_0001 && ram[2] === 32'hBBBB_0002)
            pass("both contended stores written");
        else
            fail("both contended stores written");

        // ── Test 6: back-to-back fetch→store loop (boot-copy shape) ──
        // The CPU holds cyc across the SPI fetch and the RAM store; the
        // address switches between slaves without ever dropping cyc.
        begin : t6
            integer i;
            for (i = 0; i < 3; i = i + 1) begin
                // fetch
                c0_cyc = 1; c0_stb = 1; c0_we = 0;
                c0_adr = 32'h2000_0100 + i * 4; c0_sel = 4'hF;
                run_c0_until_ack;
                // immediately store the fetched word, cyc held
                c0_we = 1;
                c0_stb = 1;
                c0_adr = 32'h8000_0010 + i * 4;
                c0_dat_wr = c0_dat_rd;
                c0_sel = 4'hF;
                run_c0_until_ack;
                c0_cyc = 0;
            end
            @(posedge clock); #1;
            if (ram[4] === 32'h12340000 && ram[5] === 32'h12340004
                && ram[6] === 32'h12340008)
                pass("back-to-back fetch->store loop copies correctly");
            else begin
                fail("back-to-back fetch->store loop copies correctly");
                $display("  ram[4]=%08x ram[5]=%08x ram[6]=%08x",
                         ram[4], ram[5], ram[6]);
            end
        end

        // ── Test 7: parallel clients on distinct servers ─────────────
        // c0 fetches from SPI while c1 simultaneously stores to RAM.
        // Each server has its own arbiter, so neither client's latency
        // may be inflated by the other, and neither response may
        // cross-wire onto the wrong client.
        begin : t7
            integer n, lat0, lat1;
            reg saw0, saw1;
            c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_adr = 32'h2000_0200; c0_sel = 4'hF;
            c1_cyc = 1; c1_stb = 1; c1_we = 1; c1_adr = 32'h8000_0020;
            c1_dat_wr = 32'hC0DE_0007; c1_sel = 4'hF;
            ack0_evt = 0; ack1_evt = 0;
            saw0 = 0; saw1 = 0; lat0 = 0; lat1 = 0;
            n = 0;
            while (!(saw0 && saw1) && n < 200) begin
                @(posedge clock); #1; n = n + 1;
                if (ack0_evt === 1'b1 && !saw0) begin
                    saw0 = 1; lat0 = n; d0 = c0_dat_rd;
                end
                if (ack1_evt === 1'b1 && !saw1) begin
                    saw1 = 1; lat1 = n;
                end
            end
            c0_cyc = 0; c0_stb = 0; c1_cyc = 0; c1_stb = 0;
            if (saw0 && saw1) pass("parallel clients on distinct servers complete");
            else fail("parallel clients on distinct servers complete");
            if (saw0 && saw1 && lat1 < lat0)
                pass("RAM client not delayed by concurrent SPI fetch");
            else if (saw0 && saw1)
                fail("RAM client not delayed by concurrent SPI fetch");
            if (ram[8] === 32'hC0DE_0007) pass("parallel c1 RAM store lands");
            else fail("parallel c1 RAM store lands");
            if (d0 === 32'h1234_0000) pass("parallel c0 SPI read data correct");
            else fail("parallel c0 SPI read data correct");
        end

        // ── Test 8: byte-lane (sel) handling through the crossbar ────
        // Subword stores must carry sel unchanged to the slave, and the
        // slave's read data must come back unharmed.
        begin : t8
            c0_cyc = 1; c0_stb = 1; c0_we = 1; c0_adr = 32'h8000_0040;
            c0_dat_wr = 32'hFFFF_FFFF; c0_sel = 4'hF;
            run_c0_until_ack;
            c0_cyc = 0;
            c0_cyc = 1; c0_stb = 1; c0_we = 1; c0_adr = 32'h8000_0040;
            c0_dat_wr = 32'hAABB_CCDD; c0_sel = 4'b0001;
            run_c0_until_ack;
            c0_cyc = 0;
            if (ram[16] === 32'hFFFF_FFDD) pass("store honours sel=0001 (lane 0 only)");
            else fail("store honours sel=0001 (lane 0 only)");
            c0_cyc = 1; c0_stb = 1; c0_we = 1; c0_adr = 32'h8000_0040;
            c0_dat_wr = 32'h1122_3344; c0_sel = 4'b1110;
            run_c0_until_ack;
            c0_cyc = 0;
            if (ram[16] === 32'h1122_33DD) pass("store honours sel=1110 (lanes 1..3)");
            else fail("store honours sel=1110 (lanes 1..3)");
            c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_adr = 32'h8000_0040; c0_sel = 4'hF;
            run_c0_until_ack;
            if (c0_dat_rd === 32'h1122_33DD) pass("readback merges byte lanes");
            else fail("readback merges byte lanes");
            c0_cyc = 0;
        end

        // ── Test 9: slave err propagates to the requesting client ────
        // The TB forces s2_err for one transaction; client_1 must see
        // err, and must NOT see a spurious ack alongside it.
        begin : t9
            integer n;
            reg saw_err, saw_ack;
            s2_err_r = 1;
            c1_cyc = 1; c1_stb = 1; c1_we = 0; c1_adr = 32'h8000_0080; c1_sel = 4'hF;
            saw_err = 0; saw_ack = 0;
            n = 0;
            while (!saw_err && n < 50) begin
                @(posedge clock); #1; n = n + 1;
                if (c1_err === 1'b1) saw_err = 1;
                if (c1_ack === 1'b1) saw_ack = 1;
            end
            c1_cyc = 0; c1_stb = 0;
            s2_err_r = 0;
            @(posedge clock); #1;
            if (saw_err && !saw_ack) pass("RAM err reaches client_1 without a spurious ack");
            else fail("RAM err reaches client_1 without a spurious ack");
        end

        // ── Test 10: sustained contention — both clients progress ────
        // Both masters behave like real Wishbone burst masters: strobe
        // stays high except for one idle strobe cycle after each own
        // ack.  Neither client may be shut out: both must accumulate a
        // comparable number of acks, and every store must land intact.
        begin : t10
            c0_cyc = 1; c0_stb = 1; c0_we = 1; c0_sel = 4'hF;
            c0_adr = 32'h8000_0100; c0_dat_wr = 32'hFA00_0000;
            c1_cyc = 1; c1_stb = 1; c1_we = 1; c1_sel = 4'hF;
            c1_adr = 32'h8000_0300; c1_dat_wr = 32'hFB00_0000;
            acks0 = 0; acks1 = 0;
            ack0_evt = 0; ack1_evt = 0;
            fork
                begin : t10_c0
                    integer n, got;
                    got = 0;
                    for (n = 0; n < 400 && got < 64; n = n + 1) begin
                        @(posedge clock); #1;
                        // Sample the registered ack probe: a combinational
                        // slave's raw ack rises combinationaly at grant
                        // time, before the served cycle completes.  A real
                        // master reacts at the clock edge that ends the
                        // acked cycle — exactly what the probe captures.
                        if (ack0_evt === 1'b1) begin
                            got = got + 1; acks0 = acks0 + 1;
                            c0_stb = 0;                  // one strobe gap
                            c0_adr = c0_adr + 4;
                            c0_dat_wr = c0_dat_wr + 1;
                        end else begin
                            c0_stb = 1;
                        end
                    end
                    c0_stb = 0; c0_cyc = 0;
                end
                begin : t10_c1
                    integer n, got;
                    got = 0;
                    for (n = 0; n < 400 && got < 64; n = n + 1) begin
                        @(posedge clock); #1;
                        if (ack1_evt === 1'b1) begin
                            got = got + 1; acks1 = acks1 + 1;
                            c1_stb = 0;
                            c1_adr = c1_adr + 4;
                            c1_dat_wr = c1_dat_wr + 1;
                        end else begin
                            c1_stb = 1;
                        end
                    end
                    c1_stb = 0; c1_cyc = 0;
                end
            join
            $display("  contention acks: client_0=%0d client_1=%0d", acks0, acks1);
            if (acks0 >= 32 && acks1 >= 32)
                pass("sustained contention: both clients progress");
            else
                fail("sustained contention: both clients progress");
            begin : t10_diff
                integer diff;
                diff = (acks0 > acks1) ? (acks0 - acks1) : (acks1 - acks0);
                if (diff <= 8) pass("sustained contention: balanced service");
                else fail("sustained contention: balanced service");
            end
            begin : t10_data
                integer i, bad;
                bad = 0;
                for (i = 0; i < acks0; i = i + 1)
                    if (ram[64+i] !== (32'hFA00_0000 + i)) bad = 1;
                for (i = 0; i < acks1; i = i + 1)
                    if (ram[192+i] !== (32'hFB00_0000 + i)) bad = 1;
                if (!bad) pass("sustained contention: all stores land intact");
                else fail("sustained contention: all stores land intact");
            end
        end

        // ── Test 11: unmapped addresses never grant any server ───────
        // Adr[31:29] outside {001,010,100} decodes to dontcare.  No
        // server may see a grant, and the client must not get a ack.
        // (Documented behavior: the transaction simply never completes
        // — the crossbar has no decode-error response.)
        begin : t11
            integer m, mm;
            reg any_serve, saw_ack;
            for (m = 0; m < 5; m = m + 1) begin
                c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_sel = 4'hF;
                case (m)
                    0: c0_adr = 32'h0000_0000;
                    1: c0_adr = 32'h6000_0000;
                    2: c0_adr = 32'hA000_0000;
                    3: c0_adr = 32'hC000_0000;
                    4: c0_adr = 32'hE000_0000;
                endcase
                any_serve = 0; saw_ack = 0;
                for (mm = 0; mm < 6; mm = mm + 1) begin
                    @(posedge clock); #1;
                    if (s0_cyc || s1_cyc || s2_cyc) any_serve = 1;
                    if (c0_ack === 1'b1) saw_ack = 1;
                end
                c0_cyc = 0; c0_stb = 0;
                @(posedge clock); #1;
                if (!any_serve && !saw_ack)
                    $display("pass: unmapped %h: no grant, no phantom, no ack (bus waits)", c0_adr);
                else begin
                    errors = errors + 1;
                    $display("FAIL: unmapped %h caused a grant/ack", c0_adr);
                end
            end
        end

        // ── Test 12: mid-transaction grant switch (CPU-like) ─────────
        // c0 starts an SPI fetch, then — before the SPI stub acks —
        // switches its address to a RAM store with cyc held, exactly
        // like the CPU coming out of a flash fetch.  Checks the three
        // documented gating properties:
        //   a) the SPI server never sees a phantom strobe (its wait
        //      counter freezes, it never acks),
        //   b) no stale SPI ack leaks to client_0,
        //   c) the RAM store completes normally and the read mux has
        //      followed the new grant.
        begin : t12
            c0_cyc = 1; c0_stb = 1; c0_we = 0; c0_adr = 32'h2000_0300; c0_sel = 4'hF;
            s0_wait = 0;                 // fresh SPI wait counter
            s0_acked = 0;
            repeat (3) @(posedge clock); #1;
            if (s0_acked !== 1'b0) fail("t12 precondition: SPI must not have acked yet");
            c0_we = 1; c0_adr = 32'h8000_0060;
            c0_dat_wr = 32'hABBA_CAFE; c0_sel = 4'hF;
            run_c0_until_ack;
            if (lat == 2) pass("post-switch RAM store acks in 2 strobe cycles");
            else if (lat == 1) pass("post-switch RAM store acks in 1 strobe cycle");
            else fail("post-switch RAM store latency");
            if (ram[24] === 32'hABBA_CAFE) pass("post-switch RAM store lands");
            else fail("post-switch RAM store lands");
            if (c0_dat_rd === 32'hABBA_CAFE) pass("client_0 read mux follows the new grant");
            else fail("client_0 read mux follows the new grant");
            if (!s0_acked && s0_wait < SPI_LATENCY)
                pass("aborted SPI fetch: no phantom strobe, no stale ack");
            else
                fail("aborted SPI fetch: no phantom strobe, no stale ack");
            c0_cyc = 0;
        end

        // ── Test 13: queued client re-targets another server ─────────
        // c0 hogs RAM with back-to-back stores; c1 queues on RAM, then
        // re-targets SPI without dropping cyc.  c1 must be granted the
        // (idle) SPI server immediately and read SPI data — not RAM
        // data — through the grant mux.
        begin : t13
            integer n;
            reg got;
            c0_cyc = 1; c0_stb = 1; c0_we = 1; c0_sel = 4'hF;
            c0_adr = 32'h8000_0200; c0_dat_wr = 32'hDA00_0000;
            c1_cyc = 1; c1_stb = 1; c1_we = 0; c1_adr = 32'h8000_0240; c1_sel = 4'hF;
            repeat (3) @(posedge clock); #1;   // c1 queued behind c0 on RAM
            if (c1_ack === 1'b1) fail("t13 precondition: c1 should be waiting");
            c1_adr = 32'h2000_0380;            // re-target SPI, cyc held
            repeat (4) begin                   // c0 keeps servicing RAM
                @(posedge clock); #1;
                c0_adr = c0_adr + 4; c0_dat_wr = c0_dat_wr + 1;
            end
            c0_cyc = 0; c0_stb = 0;            // free the RAM port
            ack1_evt = 0;
            n = 0; got = 0;
            while (!got && n < 100) begin
                @(posedge clock); #1; n = n + 1;
                if (ack1_evt === 1'b1) begin got = 1; d1 = c1_dat_rd; end
            end
            c1_cyc = 0; c1_stb = 0;
            if (got && d1 === 32'h1234_0080)
                pass("queued re-target re-grants new server with correct read data");
            else begin
                fail("queued re-target re-grants new server with correct read data");
                $display("  d1=%h got=%b", d1, got);
            end
        end

        if (errors == 0)
            $display("ALL CROSSBAR TESTS PASSED");
        else
            $display("%0d CROSSBAR TEST(S) FAILED", errors);
        $finish;
    end

    // global watchdog
    initial begin
        #100000;
        $display("FAIL: watchdog timeout");
        $finish;
    end
endmodule
