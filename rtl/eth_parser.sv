// =============================================================================
// eth_parser.sv - Ethernet Frame Parser
// =============================================================================
// Strips the 14-byte Ethernet header and passes the IP payload through.
// Drops frames with non-IPv4 EtherType.
//
// Ethernet Header (14 bytes):
//   [0:5]   Destination MAC (6 bytes)
//   [6:11]  Source MAC (6 bytes)
//   [12:13] EtherType (2 bytes) - must be 0x0800 for IPv4
//
// Interface: AXI-Stream in -> AXI-Stream out
//   - 8-bit data width (1 byte per clock)
//   - tvalid/tready handshake
//   - tlast marks end of frame
// =============================================================================

module eth_parser
    import itch_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Stream Input (raw Ethernet bytes)
    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // AXI-Stream Output (IP payload bytes)
    output logic [7:0]  m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    // Status outputs (optional, for debugging/statistics)
    output logic        frame_dropped,     // Pulse: frame was dropped (bad EtherType)
    output logic        frame_accepted     // Pulse: frame passed through
);

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        S_HEADER,       // Receiving the 14-byte Ethernet header
        S_PAYLOAD,      // Passing through the IP payload
        S_DROP          // Dropping the rest of a bad frame
    } state_t;

    state_t state, state_next;

    // =========================================================================
    // Byte Counter
    // =========================================================================
    logic [3:0] byte_cnt;       // Counts 0..13 during header reception
    logic [3:0] byte_cnt_next;

    // =========================================================================
    // Header Fields
    // =========================================================================
    logic [15:0] ethertype;
    logic [15:0] ethertype_next;

    // =========================================================================
    // Handshake: transfer happens when both valid and ready are high
    // =========================================================================
    logic transfer_in;
    assign transfer_in = s_axis_tvalid & s_axis_tready;

    // =========================================================================
    // State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_HEADER;
            byte_cnt  <= 4'd0;
            ethertype <= 16'd0;
        end else begin
            state     <= state_next;
            byte_cnt  <= byte_cnt_next;
            ethertype <= ethertype_next;
        end
    end

    // =========================================================================
    // Next-State Logic
    // =========================================================================
    always_comb begin
        // Defaults
        state_next     = state;
        byte_cnt_next  = byte_cnt;
        ethertype_next = ethertype;

        m_axis_tdata   = 8'd0;
        m_axis_tvalid  = 1'b0;
        m_axis_tlast   = 1'b0;
        s_axis_tready  = 1'b0;

        frame_dropped  = 1'b0;
        frame_accepted = 1'b0;

        case (state)
            // -----------------------------------------------------------------
            // S_HEADER: Absorb the 14-byte Ethernet header
            // -----------------------------------------------------------------
            S_HEADER: begin
                // Always ready to accept header bytes (we're just storing them)
                s_axis_tready = 1'b1;

                if (transfer_in) begin
                    // Capture EtherType bytes (bytes 12 and 13)
                    if (byte_cnt == 4'd12)
                        ethertype_next[15:8] = s_axis_tdata;
                    else if (byte_cnt == 4'd13)
                        ethertype_next[7:0] = s_axis_tdata;

                    if (s_axis_tlast) begin
                        // Frame ended during header - too short, just reset
                        byte_cnt_next = 4'd0;
                        state_next    = S_HEADER;
                        frame_dropped = 1'b1;
                    end else if (byte_cnt == 4'd13) begin
                        // We've received all 14 header bytes
                        // Check EtherType (combine stored MSB with current LSB)
                        if ({ethertype[15:8], s_axis_tdata} == ETHERTYPE_IPV4) begin
                            state_next     = S_PAYLOAD;
                            frame_accepted = 1'b1;
                        end else begin
                            state_next    = S_DROP;
                            frame_dropped = 1'b1;
                        end
                        byte_cnt_next = 4'd0;
                    end else begin
                        byte_cnt_next = byte_cnt + 4'd1;
                    end
                end
            end

            // -----------------------------------------------------------------
            // S_PAYLOAD: Pass through IP payload bytes
            // -----------------------------------------------------------------
            S_PAYLOAD: begin
                // Pass-through: connect input directly to output
                m_axis_tdata  = s_axis_tdata;
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tlast  = s_axis_tlast;
                s_axis_tready = m_axis_tready;

                if (transfer_in && s_axis_tlast) begin
                    // End of frame, go back to header state
                    state_next = S_HEADER;
                end
            end

            // -----------------------------------------------------------------
            // S_DROP: Consume and discard remaining bytes of a bad frame
            // -----------------------------------------------------------------
            S_DROP: begin
                s_axis_tready = 1'b1;  // Keep consuming

                if (transfer_in && s_axis_tlast) begin
                    state_next = S_HEADER;
                end
            end

            default: begin
                state_next = S_HEADER;
            end
        endcase
    end

endmodule
