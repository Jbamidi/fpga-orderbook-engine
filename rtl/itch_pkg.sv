package itch_pkg;

    // ITCH Message Types
    typedef enum logic [7:0] {
        MSG_ADD_ORDER       = 8'h41,  // 'A'
        MSG_ORDER_CANCEL    = 8'h58,  // 'X'
        MSG_ORDER_EXECUTED  = 8'h45,  // 'E'
        MSG_ORDER_REPLACE   = 8'h55   // 'U'
    } itch_msg_type_t;

    // Network Constants
    localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
    localparam logic [7:0]  IP_PROTO_UDP   = 8'h11;

    localparam int ETH_HEADER_BYTES = 14;
    localparam int IP_HEADER_BYTES  = 20;  // No options
    localparam int UDP_HEADER_BYTES = 8;
    localparam int TOTAL_HEADER_BYTES = ETH_HEADER_BYTES + IP_HEADER_BYTES + UDP_HEADER_BYTES;

    // ITCH Message Sizes (in bytes, including message type byte)
    localparam int ADD_ORDER_BYTES      = 36;
    localparam int ORDER_CANCEL_BYTES   = 23;
    localparam int ORDER_EXECUTED_BYTES = 31;
    localparam int ORDER_REPLACE_BYTES  = 35;
    
    // Decoded ITCH Message Struct
    // This is the output of the ITCH decoder - a clean, unpacked struct
    // that the order book engine consumes.

    typedef struct packed {
        itch_msg_type_t msg_type;       // What kind of message
        logic [63:0]    order_ref;      // Order reference number (unique ID)
        logic [63:0]    new_order_ref;  // New reference (REPLACE only)
        logic           side;           // 1 = Buy, 0 = Sell
        logic [31:0]    shares;         // Number of shares
        logic [63:0]    stock;          // Stock ticker (8 ASCII chars)
        logic [31:0]    price;          // Price (fixed-point, x10000)
        logic [47:0]    timestamp;      // Nanoseconds since midnight
        logic [63:0]    match_number;   // Match number (EXECUTE only)
        logic           valid;          // Message is valid and ready
    } itch_msg_t;

    // Order Book Entry
    typedef struct packed {
        logic           active;         // Entry is valid/in-use
        logic           side;           // 1 = Buy, 0 = Sell
        logic [31:0]    price;          // Price (fixed-point, x10000)
        logic [31:0]    shares;         // Remaining shares
        logic [63:0]    stock;          // Stock ticker
        logic [63:0]    order_ref;      // Order reference number
    } order_entry_t;

    // Top-of-Book Output
    typedef struct packed {
        logic [31:0]    best_bid;       // Highest buy price
        logic [31:0]    best_ask;       // Lowest sell price
        logic [31:0]    bid_shares;     // Shares at best bid
        logic [31:0]    ask_shares;     // Shares at best ask
        logic           valid;          // Book has been updated
    } top_of_book_t;

    // Side Encoding
    localparam logic SIDE_BUY  = 1'b1;
    localparam logic SIDE_SELL = 1'b0;
    localparam logic [7:0] ASCII_B = 8'h42;  // 'B'
    localparam logic [7:0] ASCII_S = 8'h53;  // 'S'

endpackage
