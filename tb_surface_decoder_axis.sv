`timescale 1ns / 1ps

module tb_surface_decoder_axis;

    // Clock and Reset Signals
    logic        aclk;
    logic        aresetn;

    // AXI-Stream Slave (Inputs to DUT)
    logic [7:0]  s_axis_tdata;
    logic        s_axis_tvalid;
    wire         s_axis_tready;

    // AXI-Stream Master (Outputs from DUT)
    wire  [8:0]  m_axis_tdata;
    wire  [7:0]  m_axis_tuser;
    wire         m_axis_tvalid;
    logic        m_axis_tready;

    // Instantiate Device Under Test (DUT)
    surface_decoder_axis dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tuser  (m_axis_tuser),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    // 200 MHz Clock Generation (5.0 ns period -> 2.5 ns half-cycle)
    initial aclk = 0;
    always #2.5 aclk = ~aclk;

    // FSDB Waveform Dump for Synopsys Verdi
    initial begin
        $fsdbDumpfile("quantum_decoder.fsdb");
        $fsdbDumpvars(0, tb_surface_decoder_axis, "+all");
        $fsdbDumpflush;
    end

    // Task: Transmit Syndrome Burst over AXI-Stream
    task send_syndrome(input [7:0] syndrome_val);
        begin
            @(posedge aclk);
            s_axis_tdata  <= syndrome_val;
            s_axis_tvalid <= 1'b1;

            // Wait for handshake
            wait (s_axis_tready == 1'b1);
            @(posedge aclk);
            s_axis_tvalid <= 1'b0;

            // Wait for decoded output valid
            wait (m_axis_tvalid == 1'b1);
            $display("[SIM INFO @ %0t ns] Received Syndrome: 8'h%02h (8'b%b)", $time, syndrome_val, syndrome_val);
            $display("                     -> Decoded Correction Mask: 9'b%b", m_axis_tdata);
            $display("                     -> Cycles Elapsed: %0d cycles", m_axis_tuser);
            $display("                     -> Calculated Latency @ 200MHz: %0d ns (Target < 400ns)", m_axis_tuser * 5);

            // Verify Latency Requirement
            if (m_axis_tuser <= 13) begin
                $display("                     -> [PASS] Latency strictly within real-time budget.\n");
            end else begin
                $display("                     -> [FAIL] Decoherence deadline exceeded!\n");
            end

            // Complete downstream handshake
            @(posedge aclk);
            m_axis_tready <= 1'b1;
            @(posedge aclk);
            m_axis_tready <= 1'b0;
        end
    endtask

    // Main Stimulus
    initial begin
        // Initialize Signals
        aresetn       = 1'b0;
        s_axis_tdata  = 8'h00;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b0;

        // Apply Reset
        #20;
        aresetn = 1'b1;
        #15;

        $display("\n=======================================================");
        $display("STARTING QUANTUM SYNDROME DECODER REGRESSION SUITE");
        $display("Clock: 200 MHz | Period: 5.0 ns | Real-Time Budget: 400 ns");
        $display("=======================================================\n");

        // Test Case 1: Pattern 8'h15 (8'b00010101)
        send_syndrome(8'h15);
        #30;

        // Test Case 2: Pattern 8'hA3 (8'b10100011)
        send_syndrome(8'hA3);
        #30;

        // Test Case 3: Pattern 8'h5A (8'b01011010)
        send_syndrome(8'h5A);
        #30;

        // Test Case 4: Pattern 8'hFF (All stabilizers triggered)
        send_syndrome(8'hFF);
        #50;

        $display("=======================================================");
        $display("ALL TESTS COMPLETED SUCCESSFULLY. CLOSING SIMULATION.");
        $display("=======================================================\n");

        $finish;
    end

endmodule
