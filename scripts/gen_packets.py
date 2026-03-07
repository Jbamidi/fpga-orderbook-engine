#!/usr/bin/env python3
"""
ITCH 5.0 Test Packet Generator
===============================
Generates raw binary packets: Ethernet + IP + UDP + ITCH message
Outputs hex files readable by SystemVerilog $readmemh

This is your single source of truth for testing the entire pipeline.
Every time you add a new feature, extend this script first.
"""

import struct
import random
import json
import os

# Constants
# Ethernet
DST_MAC = bytes([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
SRC_MAC = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
ETHERTYPE_IP = 0x0800

# IP
IP_VERSION_IHL = 0x45   # IPv4, 20-byte header (no options)
IP_TTL = 64
IP_PROTOCOL_UDP = 0x11

SRC_IP = bytes([192, 168, 1, 1])
DST_IP = bytes([192, 168, 1, 2])

# UDP
SRC_PORT = 12345
DST_PORT = 26400  # Typical ITCH feed port

# ITCH 5.0 Message Types
ITCH_ADD_ORDER       = ord('A')  # 0x41
ITCH_ORDER_CANCEL    = ord('X')  # 0x58
ITCH_ORDER_EXECUTED  = ord('E')  # 0x45
ITCH_ORDER_REPLACE   = ord('U')  # 0x55

# Helper Functions

def ip_checksum(header_bytes):
    """Compute IP header checksum (RFC 1071)."""
    if len(header_bytes) % 2 == 1:
        header_bytes += b'\x00'
    s = 0
    for i in range(0, len(header_bytes), 2):
        w = (header_bytes[i] << 8) + header_bytes[i + 1]
        s += w
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return ~s & 0xFFFF


def build_ethernet_header(ethertype=ETHERTYPE_IP):
    """14 bytes: dst_mac(6) + src_mac(6) + ethertype(2)"""
    return DST_MAC + SRC_MAC + struct.pack('!H', ethertype)


def build_ip_header(payload_length):
    """20 bytes: standard IPv4 header with no options."""
    total_length = 20 + payload_length
    identification = random.randint(0, 0xFFFF)
    flags_fragment = 0x4000  # Don't Fragment

    # Build header with checksum = 0 first
    header = struct.pack('!BBHHHBBH4s4s',
        IP_VERSION_IHL,      # Version + IHL
        0,                   # DSCP/ECN
        total_length,        # Total Length
        identification,      # Identification
        flags_fragment,      # Flags + Fragment Offset
        IP_TTL,              # TTL
        IP_PROTOCOL_UDP,     # Protocol (UDP)
        0,                   # Checksum (placeholder)
        SRC_IP,              # Source IP
        DST_IP               # Destination IP
    )

    # Compute and insert checksum
    chksum = ip_checksum(header)
    header = header[:10] + struct.pack('!H', chksum) + header[12:]
    return header


def build_udp_header(payload_length):
    """8 bytes: src_port(2) + dst_port(2) + length(2) + checksum(2)"""
    udp_length = 8 + payload_length
    return struct.pack('!HHHH',
        SRC_PORT,
        DST_PORT,
        udp_length,
        0  # Checksum (0 = disabled, valid for UDP)
    )



# ITCH Message Builders

def build_add_order(order_ref, side, shares, stock, price, timestamp=None):
    """
    Add Order (Type 'A') - 36 bytes total:
      msg_type(1) + locate(2) + tracking(2) + timestamp(6) +
      order_ref(8) + side(1) + shares(4) + stock(8) + price(4)

    Args:
        order_ref: Unique order reference number (int, 8 bytes)
        side: 'B' for buy, 'S' for sell
        shares: Number of shares (int, 4 bytes)
        stock: Stock ticker string (up to 8 chars, right-padded with spaces)
        price: Price in fixed-point (int, 4 bytes) - actual price * 10000
        timestamp: Nanoseconds since midnight (int, 6 bytes) or None for random
    """
    if timestamp is None:
        timestamp = random.randint(0, 57600000000000)  # Up to 16 hours in ns

    stock_padded = stock.ljust(8)[:8].encode('ascii')

    return struct.pack('!c HH',
        bytes([ITCH_ADD_ORDER]),  # Message type
        0,                        # Stock locate
        0,                        # Tracking number
    ) + timestamp.to_bytes(6, 'big') + struct.pack('!Qc I 8s I',
        order_ref,
        side.encode('ascii'),
        shares,
        stock_padded,
        price,
    )


def build_order_cancel(order_ref, cancelled_shares, timestamp=None):
    """
    Order Cancel (Type 'X') - 23 bytes total:
      msg_type(1) + locate(2) + tracking(2) + timestamp(6) +
      order_ref(8) + cancelled_shares(4)
    """
    if timestamp is None:
        timestamp = random.randint(0, 57600000000000)

    return struct.pack('!c HH',
        bytes([ITCH_ORDER_CANCEL]),
        0, 0,
    ) + timestamp.to_bytes(6, 'big') + struct.pack('!Q I',
        order_ref,
        cancelled_shares,
    )


def build_order_executed(order_ref, executed_shares, match_number, timestamp=None):
    """
    Order Executed (Type 'E') - 31 bytes total:
      msg_type(1) + locate(2) + tracking(2) + timestamp(6) +
      order_ref(8) + executed_shares(4) + match_number(8)
    """
    if timestamp is None:
        timestamp = random.randint(0, 57600000000000)

    return struct.pack('!c HH',
        bytes([ITCH_ORDER_EXECUTED]),
        0, 0,
    ) + timestamp.to_bytes(6, 'big') + struct.pack('!Q I Q',
        order_ref,
        executed_shares,
        match_number,
    )


def build_order_replace(original_ref, new_ref, new_shares, new_price, timestamp=None):
    """
    Order Replace (Type 'U') - 35 bytes total:
      msg_type(1) + locate(2) + tracking(2) + timestamp(6) +
      original_ref(8) + new_ref(8) + new_shares(4) + new_price(4)
    """
    if timestamp is None:
        timestamp = random.randint(0, 57600000000000)

    return struct.pack('!c HH',
        bytes([ITCH_ORDER_REPLACE]),
        0, 0,
    ) + timestamp.to_bytes(6, 'big') + struct.pack('!Q Q I I',
        original_ref,
        new_ref,
        new_shares,
        new_price,
    )


# Full Packet Builder


def build_full_packet(itch_message):
    """Wrap an ITCH message in UDP + IP + Ethernet headers."""
    udp_payload = itch_message
    udp_header = build_udp_header(len(udp_payload))
    ip_payload = udp_header + udp_payload
    ip_header = build_ip_header(len(ip_payload))
    eth_header = build_ethernet_header()
    return eth_header + ip_header + ip_payload


def build_bad_ethertype_packet():
    """Generate a packet with wrong EtherType (should be dropped)."""
    itch_msg = build_add_order(999, 'B', 100, 'JUNK', 10000)
    udp_header = build_udp_header(len(itch_msg))
    ip_header = build_ip_header(len(udp_header) + len(itch_msg))
    eth_header = build_ethernet_header(ethertype=0x86DD)  # IPv6 ethertype, should be dropped
    return eth_header + ip_header + udp_header + itch_msg



# Output Generators

def packets_to_hex_file(packets, filepath):
    """
    Write packets to a hex file readable by $readmemh.
    Format: one byte per line in hex (e.g., "A5").
    Packets separated by "FF" marker line (0xFF as inter-packet gap).

    We use a simple framing scheme:
    - Each packet is preceded by a 2-byte length (big-endian)
    - This lets the testbench know how many bytes to read
    """
    with open(filepath, 'w') as f:
        for pkt in packets:
            # Write 2-byte length prefix
            pkt_len = len(pkt)
            f.write(f'{(pkt_len >> 8) & 0xFF:02X}\n')
            f.write(f'{pkt_len & 0xFF:02X}\n')
            # Write packet bytes
            for byte in pkt:
                f.write(f'{byte:02X}\n')
        # End marker
        f.write('00\n00\n')


def packets_to_binary(packets, filepath):
    """Write raw packets to a binary file."""
    with open(filepath, 'wb') as f:
        for pkt in packets:
            f.write(struct.pack('!H', len(pkt)))
            f.write(pkt)


def generate_reference_model(messages, filepath):
    """
    Run a Python reference model on the ITCH messages and output
    expected order book state after each message.

    This is your golden reference for verification.
    """
    order_book = {}  # order_ref -> {side, price, shares, stock}
    results = []

    for msg in messages:
        msg_type = msg['type']

        if msg_type == 'ADD':
            order_book[msg['order_ref']] = {
                'side': msg['side'],
                'price': msg['price'],
                'shares': msg['shares'],
                'stock': msg['stock'],
            }

        elif msg_type == 'CANCEL':
            ref = msg['order_ref']
            if ref in order_book:
                order_book[ref]['shares'] -= msg['cancelled_shares']
                if order_book[ref]['shares'] <= 0:
                    del order_book[ref]

        elif msg_type == 'EXECUTE':
            ref = msg['order_ref']
            if ref in order_book:
                order_book[ref]['shares'] -= msg['executed_shares']
                if order_book[ref]['shares'] <= 0:
                    del order_book[ref]

        elif msg_type == 'REPLACE':
            orig_ref = msg['original_ref']
            new_ref = msg['new_ref']
            if orig_ref in order_book:
                old = order_book.pop(orig_ref)
                order_book[new_ref] = {
                    'side': old['side'],
                    'price': msg['new_price'],
                    'shares': msg['new_shares'],
                    'stock': old['stock'],
                }

        # Compute top of book
        bids = [o for o in order_book.values() if o['side'] == 'B']
        asks = [o for o in order_book.values() if o['side'] == 'S']

        best_bid = max((o['price'] for o in bids), default=0)
        best_ask = min((o['price'] for o in asks), default=0xFFFFFFFF)

        results.append({
            'msg_index': len(results),
            'msg_type': msg_type,
            'best_bid': best_bid,
            'best_ask': best_ask,
            'num_orders': len(order_book),
        })

    with open(filepath, 'w') as f:
        json.dump(results, f, indent=2)

    return results



# Test Scenario Generator

def generate_test_scenario(num_orders=100, seed=42):
    """
    Generate a realistic sequence of ITCH messages.
    Returns both the raw packets and the message metadata for the reference model.
    """
    random.seed(seed)

    packets = []
    messages = []
    active_orders = {}
    next_order_ref = 1
    next_match = 1

    stocks = ['AAPL    ', 'MSFT    ', 'GOOG    ', 'TSLA    ']
    base_prices = {'AAPL    ': 1500000, 'MSFT    ': 3800000,
                   'GOOG    ': 1400000, 'TSLA    ': 2500000}

    for i in range(num_orders):
        # Decide what type of message to generate
        # Bias toward ADD orders, especially at the start
        if len(active_orders) < 5 or random.random() < 0.5:
            # ADD ORDER
            stock = random.choice(stocks)
            side = random.choice(['B', 'S'])
            base = base_prices[stock]
            # Price varies +/- 5% from base, in increments of 100 (1 cent)
            price = base + random.randint(-base // 20, base // 20)
            price = (price // 100) * 100  # Round to cents
            shares = random.choice([100, 200, 500, 1000, 5000])

            ref = next_order_ref
            next_order_ref += 1

            itch_msg = build_add_order(ref, side, shares, stock.strip(), price)
            packets.append(build_full_packet(itch_msg))
            messages.append({
                'type': 'ADD',
                'order_ref': ref,
                'side': side,
                'shares': shares,
                'stock': stock.strip(),
                'price': price,
            })
            active_orders[ref] = {'side': side, 'shares': shares, 'stock': stock, 'price': price}

        elif active_orders:
            action = random.choices(['CANCEL', 'EXECUTE', 'REPLACE'], weights=[0.4, 0.4, 0.2])[0]
            ref = random.choice(list(active_orders.keys()))
            order = active_orders[ref]

            if action == 'CANCEL':
                cancel_shares = random.randint(1, order['shares'])
                itch_msg = build_order_cancel(ref, cancel_shares)
                packets.append(build_full_packet(itch_msg))
                messages.append({
                    'type': 'CANCEL',
                    'order_ref': ref,
                    'cancelled_shares': cancel_shares,
                })
                order['shares'] -= cancel_shares
                if order['shares'] <= 0:
                    del active_orders[ref]

            elif action == 'EXECUTE':
                exec_shares = random.randint(1, order['shares'])
                match_num = next_match
                next_match += 1
                itch_msg = build_order_executed(ref, exec_shares, match_num)
                packets.append(build_full_packet(itch_msg))
                messages.append({
                    'type': 'EXECUTE',
                    'order_ref': ref,
                    'executed_shares': exec_shares,
                    'match_number': match_num,
                })
                order['shares'] -= exec_shares
                if order['shares'] <= 0:
                    del active_orders[ref]

            elif action == 'REPLACE':
                new_ref = next_order_ref
                next_order_ref += 1
                new_shares = random.choice([100, 200, 500, 1000])
                base = base_prices[order['stock']]
                new_price = base + random.randint(-base // 20, base // 20)
                new_price = (new_price // 100) * 100

                itch_msg = build_order_replace(ref, new_ref, new_shares, new_price)
                packets.append(build_full_packet(itch_msg))
                messages.append({
                    'type': 'REPLACE',
                    'original_ref': ref,
                    'new_ref': new_ref,
                    'new_shares': new_shares,
                    'new_price': new_price,
                })
                del active_orders[ref]
                active_orders[new_ref] = {
                    'side': order['side'],
                    'shares': new_shares,
                    'stock': order['stock'],
                    'price': new_price,
                }

    # Add a bad EtherType packet somewhere in the middle for testing
    bad_pkt = build_bad_ethertype_packet()
    insert_idx = len(packets) // 2
    packets.insert(insert_idx, bad_pkt)

    return packets, messages


# Main

if __name__ == '__main__':
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'sim', 'test_data')
    os.makedirs(output_dir, exist_ok=True)

    print("Generating test scenario (100 messages)...")
    packets, messages = generate_test_scenario(num_orders=100, seed=42)

    # Write hex file for $readmemh
    hex_path = os.path.join(output_dir, 'packets.hex')
    packets_to_hex_file(packets, hex_path)
    print(f"  Wrote {len(packets)} packets to {hex_path}")

    # Write binary file
    bin_path = os.path.join(output_dir, 'packets.bin')
    packets_to_binary(packets, bin_path)
    print(f"  Wrote binary packets to {bin_path}")

    # Write message metadata (for debugging)
    meta_path = os.path.join(output_dir, 'messages.json')
    with open(meta_path, 'w') as f:
        json.dump(messages, f, indent=2)
    print(f"  Wrote message metadata to {meta_path}")

    # Generate reference model output
    ref_path = os.path.join(output_dir, 'reference_output.json')
    results = generate_reference_model(messages, ref_path)
    print(f"  Wrote reference model output to {ref_path}")

    # Print summary
    print(f"\nSummary:")
    print(f"  Total packets: {len(packets)} (including 1 bad EtherType)")
    print(f"  Total ITCH messages: {len(messages)}")
    msg_types = {}
    for m in messages:
        msg_types[m['type']] = msg_types.get(m['type'], 0) + 1
    for t, c in sorted(msg_types.items()):
        print(f"    {t}: {c}")

    final = results[-1]
    print(f"\n  Final order book state:")
    print(f"    Best bid:   ${final['best_bid'] / 10000:.2f}")
    print(f"    Best ask:   ${final['best_ask'] / 10000:.2f}")
    print(f"    Active orders: {final['num_orders']}")

    print("\nDone! You can now use these files in your SystemVerilog testbench.")
