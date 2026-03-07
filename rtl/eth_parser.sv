// Strips the 14-byte Ethernet header and passes the IP payload through.
// Drops frames with non-IPv4 EtherType.

// Ethernet Header (14 bytes):
//   [0:5]   Destination MAC (6 bytes)
//   [6:11]  Source MAC (6 bytes)
//   [12:13] EtherType (2 bytes) - must be 0x0800 for IPv4

// Interface: AXI-Stream in -> AXI-Stream out
//   - 8-bit data width (1 byte per clock)
//   - tvalid/tready handshake
//   - tlast marks end of frame


module eth_parser
    import itch_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [7:0]  m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    //Testing Signals
    output logic        frame_dropped,     
    output logic        frame_accepted     
);

    typedef enum logic [1:0] {
        s_receive,       // Receiving the 14-byte Ethernet header
        s_payload,      // Passing through the IP payload
        s_drop          // Dropping the rest of a bad frame
    } state_t;

    state_t state, state_next;

    // Byte Counter
    logic [3:0] byte_cnt;       // Counts 0 to 13 during header reception
    logic [3:0] byte_cnt_next;
    logic [15:0] ethertype;
    logic [15:0] ethertype_next;
    logic accept;
    assign accept = s_axis_tvalid & s_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= s_receive;
            byte_cnt  <= 4'd0;
            ethertype <= 16'd0;
        end else begin
            state     <= state_next;
            byte_cnt  <= byte_cnt_next;
            ethertype <= ethertype_next;
        end
    end


    // Next-State Logic
    always_comb begin
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
            s_receive: begin
                s_axis_tready = 1'b1;

                if (accept) begin
                    if (byte_cnt == 4'd12)
                        ethertype_next[15:8] = s_axis_tdata;
                    else if (byte_cnt == 4'd13)
                        ethertype_next[7:0] = s_axis_tdata;

                    if (s_axis_tlast) begin
                        byte_cnt_next = 4'd0;
                        state_next    = s_receive;
                        frame_dropped = 1'b1;
                    end else if (byte_cnt == 4'd13) begin
                        if ({ethertype[15:8], s_axis_tdata} == ETHERTYPE_IPV4) begin
                            state_next     = s_payload;
                            frame_accepted = 1'b1;
                        end else begin
                            state_next    = s_drop;
                            frame_dropped = 1'b1;
                        end
                        byte_cnt_next = 4'd0;
                    end else begin
                        byte_cnt_next = byte_cnt + 4'd1;
                    end
                end
            end

            s_payload: begin
                m_axis_tdata  = s_axis_tdata;
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tlast  = s_axis_tlast;
                s_axis_tready = m_axis_tready; //Backpressure

                if (accept && s_axis_tlast) begin
                    state_next = s_receive;
                end
            end


            s_drop: begin
                s_axis_tready = 1'b1;

                if (accept && s_axis_tlast) begin
                    state_next = s_receive;
                end
            end

            default: begin
                state_next = s_receive;
            end
        endcase
    end

endmodule
