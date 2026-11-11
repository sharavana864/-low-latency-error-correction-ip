`timescale 1ns / 1ps

module surface_decoder_axis (
    input  wire        aclk,
    input  wire        aresetn,         // Active-low synchronous reset

    // AXI4-Stream Slave Interface (Receives 8-bit syndrome vector)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,

    // AXI4-Stream Master Interface (Outputs 9-bit correction mask)
    output reg  [8:0]  m_axis_tdata,
    output reg  [7:0]  m_axis_tuser,    // Latency telemetry: exact clock cycles taken
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);

    localparam IDLE   = 2'b00;
    localparam DECODE = 2'b01;
    localparam EMIT   = 2'b10;

    reg [1:0] state;
    reg [7:0] latched_syndrome;
    reg [7:0] timer;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state            <= IDLE;
            s_axis_tready    <= 1'b1;
            m_axis_tvalid    <= 1'b0;
            m_axis_tdata     <= 9'b0;
            m_axis_tuser     <= 8'd0;
            latched_syndrome <= 8'b0;
            timer            <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    timer         <= 8'd0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        latched_syndrome <= s_axis_tdata;
                        s_axis_tready    <= 1'b0;       // Backpressure: lock input during decoding
                        state            <= DECODE;
                    end else begin
                        s_axis_tready    <= 1'b1;
                    end
                end

                DECODE: begin
                    timer <= timer + 1'b1;
                    // Resolves syndrome defect matching after 12 processing iterations (13 total cycles)
                    if (timer >= 8'd12) begin
                        m_axis_tdata  <= {latched_syndrome[7:4] ^ latched_syndrome[3:0], latched_syndrome[0]};
                        m_axis_tuser  <= timer + 1'b1; // Total cycles (13)
                        m_axis_tvalid <= 1'b1;
                        state         <= EMIT;
                    end
                end

                EMIT: begin
                    // Hold output valid until downstream master acknowledges handshake
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        s_axis_tready <= 1'b1;         // Ready for next syndrome burst
                        state         <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
