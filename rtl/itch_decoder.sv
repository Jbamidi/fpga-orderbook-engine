module itch_decode
    import itch_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic        valid,
    output logic        frame_dropped,     
    output logic        frame_accepted 
);

    typedef enum logic {
        s_type,
        s_collect
    } state_t;

    state_t state, state_next;

    // Byte Counter
    logic [2:0] byte_cnt;       
    logic [2:0] byte_cnt_next;
    logic [7:0] msgtype;
    logic [7:0] msgtype_next;
    logic [47:0] timestamp;
    logic [47:0] timestamp_next;
    
    logic accept;
    assign accept = s_axis_tvalid & s_axis_tready;

    itch_msg_t order, order_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= s_type;
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

    end


endmodule

