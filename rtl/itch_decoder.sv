module itch_decode
    import itch_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output itch_msg_t   msg_out,
    output logic        msg_valid,

    output logic        frame_dropped,
    output logic        frame_accepted
);

    typedef enum logic [1:0] {
        S_TYPE,
        S_COLLECT,
        S_DROP
    } state_t;

    state_t state, state_next;

    logic [5:0]  byte_cnt,      byte_cnt_next;
    logic [5:0]  msg_len,       msg_len_next;
    logic [7:0]  msg_type_reg,  msg_type_reg_next;

    logic [47:0] r_timestamp,   r_timestamp_next;
    logic [63:0] r_order_ref,   r_order_ref_next;
    logic [63:0] r_new_order_ref, r_new_order_ref_next;
    logic [7:0]  r_side,        r_side_next;
    logic [31:0] r_shares,      r_shares_next;
    logic [63:0] r_stock,       r_stock_next;
    logic [31:0] r_price,       r_price_next;
    logic [63:0] r_match_number, r_match_number_next;

    logic accept;
    assign accept = s_axis_tvalid & s_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_TYPE;
            byte_cnt        <= 6'd0;
            msg_len         <= 6'd0;
            msg_type_reg    <= 8'd0;
            r_timestamp     <= 48'd0;
            r_order_ref     <= 64'd0;
            r_new_order_ref <= 64'd0;
            r_side          <= 8'd0;
            r_shares        <= 32'd0;
            r_stock         <= 64'd0;
            r_price         <= 32'd0;
            r_match_number  <= 64'd0;
        end else begin
            state           <= state_next;
            byte_cnt        <= byte_cnt_next;
            msg_len         <= msg_len_next;
            msg_type_reg    <= msg_type_reg_next;
            r_timestamp     <= r_timestamp_next;
            r_order_ref     <= r_order_ref_next;
            r_new_order_ref <= r_new_order_ref_next;
            r_side          <= r_side_next;
            r_shares        <= r_shares_next;
            r_stock         <= r_stock_next;
            r_price         <= r_price_next;
            r_match_number  <= r_match_number_next;
        end
    end

    function automatic logic [5:0] get_msg_len(input logic [7:0] mtype);
        case (mtype)
            MSG_ADD_ORDER:      return ADD_ORDER_BYTES[5:0];
            MSG_ORDER_CANCEL:   return ORDER_CANCEL_BYTES[5:0];
            MSG_ORDER_EXECUTED: return ORDER_EXECUTED_BYTES[5:0];
            MSG_ORDER_REPLACE:  return ORDER_REPLACE_BYTES[5:0];
            default:            return 6'd0;
        endcase
    endfunction

    function automatic logic is_known_type(input logic [7:0] mtype);
        case (mtype)
            MSG_ADD_ORDER,
            MSG_ORDER_CANCEL,
            MSG_ORDER_EXECUTED,
            MSG_ORDER_REPLACE:  return 1'b1;
            default:            return 1'b0;
        endcase
    endfunction

    always_comb begin
        state_next           = state;
        byte_cnt_next        = byte_cnt;
        msg_len_next         = msg_len;
        msg_type_reg_next    = msg_type_reg;

        r_timestamp_next     = r_timestamp;
        r_order_ref_next     = r_order_ref;
        r_new_order_ref_next = r_new_order_ref;
        r_side_next          = r_side;
        r_shares_next        = r_shares;
        r_stock_next         = r_stock;
        r_price_next         = r_price;
        r_match_number_next  = r_match_number;

        s_axis_tready  = 1'b0;
        msg_valid      = 1'b0;
        frame_dropped  = 1'b0;
        frame_accepted = 1'b0;

        msg_out.msg_type      = itch_msg_type_t'(msg_type_reg);
        msg_out.timestamp     = r_timestamp;
        msg_out.order_ref     = r_order_ref;
        msg_out.new_order_ref = r_new_order_ref;
        msg_out.side          = (r_side == ASCII_B) ? SIDE_BUY : SIDE_SELL;
        msg_out.shares        = r_shares;
        msg_out.stock         = r_stock;
        msg_out.price         = r_price;
        msg_out.match_number  = r_match_number;
        msg_out.valid         = 1'b0;

        case (state)
            S_TYPE: begin
                s_axis_tready = 1'b1;

                if (accept) begin
                    msg_type_reg_next = s_axis_tdata;

                    if (s_axis_tlast) begin
                        state_next    = S_TYPE;
                        frame_dropped = 1'b1;
                    end else if (is_known_type(s_axis_tdata)) begin
                        state_next     = S_COLLECT;
                        msg_len_next   = get_msg_len(s_axis_tdata);
                        byte_cnt_next  = 6'd1;
                        frame_accepted = 1'b1;

                        r_timestamp_next     = 48'd0;
                        r_order_ref_next     = 64'd0;
                        r_new_order_ref_next = 64'd0;
                        r_side_next          = 8'd0;
                        r_shares_next        = 32'd0;
                        r_stock_next         = 64'd0;
                        r_price_next         = 32'd0;
                        r_match_number_next  = 64'd0;
                    end else begin
                        state_next    = S_DROP;
                        frame_dropped = 1'b1;
                    end
                end
            end

            S_COLLECT: begin
                s_axis_tready = 1'b1;

                if (accept) begin
                    case (byte_cnt)
                        6'd5:  r_timestamp_next[47:40] = s_axis_tdata;
                        6'd6:  r_timestamp_next[39:32] = s_axis_tdata;
                        6'd7:  r_timestamp_next[31:24] = s_axis_tdata;
                        6'd8:  r_timestamp_next[23:16] = s_axis_tdata;
                        6'd9:  r_timestamp_next[15:8]  = s_axis_tdata;
                        6'd10: r_timestamp_next[7:0]   = s_axis_tdata;
                        default: ;
                    endcase

                    case (byte_cnt)
                        6'd11: r_order_ref_next[63:56] = s_axis_tdata;
                        6'd12: r_order_ref_next[55:48] = s_axis_tdata;
                        6'd13: r_order_ref_next[47:40] = s_axis_tdata;
                        6'd14: r_order_ref_next[39:32] = s_axis_tdata;
                        6'd15: r_order_ref_next[31:24] = s_axis_tdata;
                        6'd16: r_order_ref_next[23:16] = s_axis_tdata;
                        6'd17: r_order_ref_next[15:8]  = s_axis_tdata;
                        6'd18: r_order_ref_next[7:0]   = s_axis_tdata;
                        default: ;
                    endcase

                    case (msg_type_reg)
                        MSG_ADD_ORDER: begin
                            case (byte_cnt)
                                6'd19: r_side_next = s_axis_tdata;

                                6'd20: r_shares_next[31:24] = s_axis_tdata;
                                6'd21: r_shares_next[23:16] = s_axis_tdata;
                                6'd22: r_shares_next[15:8]  = s_axis_tdata;
                                6'd23: r_shares_next[7:0]   = s_axis_tdata;

                                6'd24: r_stock_next[63:56] = s_axis_tdata;
                                6'd25: r_stock_next[55:48] = s_axis_tdata;
                                6'd26: r_stock_next[47:40] = s_axis_tdata;
                                6'd27: r_stock_next[39:32] = s_axis_tdata;
                                6'd28: r_stock_next[31:24] = s_axis_tdata;
                                6'd29: r_stock_next[23:16] = s_axis_tdata;
                                6'd30: r_stock_next[15:8]  = s_axis_tdata;
                                6'd31: r_stock_next[7:0]   = s_axis_tdata;

                                6'd32: r_price_next[31:24] = s_axis_tdata;
                                6'd33: r_price_next[23:16] = s_axis_tdata;
                                6'd34: r_price_next[15:8]  = s_axis_tdata;
                                6'd35: r_price_next[7:0]   = s_axis_tdata;
                                default: ;
                            endcase
                        end

                        MSG_ORDER_CANCEL: begin
                            case (byte_cnt)
                                6'd19: r_shares_next[31:24] = s_axis_tdata;
                                6'd20: r_shares_next[23:16] = s_axis_tdata;
                                6'd21: r_shares_next[15:8]  = s_axis_tdata;
                                6'd22: r_shares_next[7:0]   = s_axis_tdata;
                                default: ;
                            endcase
                        end

                        MSG_ORDER_EXECUTED: begin
                            case (byte_cnt)
                                6'd19: r_shares_next[31:24] = s_axis_tdata;
                                6'd20: r_shares_next[23:16] = s_axis_tdata;
                                6'd21: r_shares_next[15:8]  = s_axis_tdata;
                                6'd22: r_shares_next[7:0]   = s_axis_tdata;

                                6'd23: r_match_number_next[63:56] = s_axis_tdata;
                                6'd24: r_match_number_next[55:48] = s_axis_tdata;
                                6'd25: r_match_number_next[47:40] = s_axis_tdata;
                                6'd26: r_match_number_next[39:32] = s_axis_tdata;
                                6'd27: r_match_number_next[31:24] = s_axis_tdata;
                                6'd28: r_match_number_next[23:16] = s_axis_tdata;
                                6'd29: r_match_number_next[15:8]  = s_axis_tdata;
                                6'd30: r_match_number_next[7:0]   = s_axis_tdata;
                                default: ;
                            endcase
                        end

                        MSG_ORDER_REPLACE: begin
                            case (byte_cnt)
                                6'd19: r_new_order_ref_next[63:56] = s_axis_tdata;
                                6'd20: r_new_order_ref_next[55:48] = s_axis_tdata;
                                6'd21: r_new_order_ref_next[47:40] = s_axis_tdata;
                                6'd22: r_new_order_ref_next[39:32] = s_axis_tdata;
                                6'd23: r_new_order_ref_next[31:24] = s_axis_tdata;
                                6'd24: r_new_order_ref_next[23:16] = s_axis_tdata;
                                6'd25: r_new_order_ref_next[15:8]  = s_axis_tdata;
                                6'd26: r_new_order_ref_next[7:0]   = s_axis_tdata;

                                6'd27: r_shares_next[31:24] = s_axis_tdata;
                                6'd28: r_shares_next[23:16] = s_axis_tdata;
                                6'd29: r_shares_next[15:8]  = s_axis_tdata;
                                6'd30: r_shares_next[7:0]   = s_axis_tdata;

                                6'd31: r_price_next[31:24] = s_axis_tdata;
                                6'd32: r_price_next[23:16] = s_axis_tdata;
                                6'd33: r_price_next[15:8]  = s_axis_tdata;
                                6'd34: r_price_next[7:0]   = s_axis_tdata;
                                default: ;
                            endcase
                        end

                        default: ;
                    endcase

                    if (s_axis_tlast) begin
                        if (byte_cnt == msg_len - 6'd1) begin
                            msg_valid     = 1'b1;
                            msg_out.valid = 1'b1;
                        end else begin
                            frame_dropped = 1'b1;
                        end
                        state_next    = S_TYPE;
                        byte_cnt_next = 6'd0;
                    end else if (byte_cnt == msg_len - 6'd1) begin
                        msg_valid     = 1'b1;
                        msg_out.valid = 1'b1;
                        state_next    = S_DROP;
                        byte_cnt_next = 6'd0;
                    end else begin
                        byte_cnt_next = byte_cnt + 6'd1;
                    end
                end
            end

            S_DROP: begin
                s_axis_tready = 1'b1;

                if (accept && s_axis_tlast) begin
                    state_next    = S_TYPE;
                    byte_cnt_next = 6'd0;
                end
            end

            default: begin
                state_next = S_TYPE;
            end
        endcase
    end

endmodule
