module udp_parser
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
    output logic        frame_dropped,     
    output logic        frame_accepted 
);

    typedef enum logic [1:0] {
        s_receive,       // Receiving the bytes
        s_payload,      // Passing through the IP payload
        s_drop          // Dropping the rest of a bad frame
    } state_t;

    state_t state, state_next;

    // Byte Counter
    logic [2:0] byte_cnt;       
    logic [2:0] byte_cnt_next;
    logic [15:0] udptype;
    logic [15:0] udptype_next;
    logic accept;
    assign accept = s_axis_tvalid & s_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= s_receive;
            byte_cnt  <= 3'd0;
            udptype <= 16'd0;
        end else begin
            state     <= state_next;
            byte_cnt  <= byte_cnt_next;
            udptype <= udptype_next;
        end
    end


    // Next-State Logic
    always_comb begin
        state_next     = state;
        byte_cnt_next  = byte_cnt;
        udptype_next = udptype;

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
                    if (byte_cnt == 3'd2)
                        udptype_next[15:8] = s_axis_tdata;
                    else if (byte_cnt == 3'd3)
                        udptype_next[7:0] = s_axis_tdata;

                    if (s_axis_tlast) begin
                        byte_cnt_next = 3'd0;
                        state_next    = s_receive;
                        frame_dropped = 1'b1;
                    end else if (byte_cnt == 3'd7) begin
                        if (udptype == 16'd26400) begin
                            state_next     = s_payload;
                            frame_accepted = 1'b1;
                        end else begin
                            state_next    = s_drop;
                            frame_dropped = 1'b1;
                        end
                        byte_cnt_next = 3'd0;
                    end else begin
                        byte_cnt_next = byte_cnt + 3'd1;
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

