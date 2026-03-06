# FPGA Order Book Engine

A hardware-accelerated market data parser and order book engine targeting low-latency processing of Nasdaq ITCH 5.0 messages on FPGA.

## Architecture

```
                         FPGA Order Book Engine
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  Raw Bytes   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │
  │ ───────────► │Ethernet │─►│  IP     │─►│  UDP   │─►│ ITCH   │ │
  │  AXI-Stream  │ Parser  │  │ Parser  │  │ Parser │  │Decoder │ │
  │              └─────────┘  └─────────┘  └─────────┘  └───┬────┘ │
  │                                                         │       │
  │              ┌──────────────────────────────────────────┐│       │
  │              │         Order Book Engine                ││       │
  │              │  ┌──────────┐    ┌──────────────────┐   │▼       │
  │              │  │  Order   │    │  Top-of-Book     │   │        │
  │              │  │  Table   │───►│  Tracker          │   │        │
  │              │  │  (BRAM)  │    │  (Best Bid/Ask)  │   │        │
  │              │  └──────────┘    └──────┬───────────┘   │        │
  │              └─────────────────────────┼───────────────┘        │
  │                                        │                        │
  │              ┌─────────────────────────▼───────────────┐        │
  │              │  AXI-Lite Register Interface            │        │
  │              │  - Best Bid/Ask                         │        │
  │              │  - Message Counters                     │        │
  │              │  - Latency Metrics                      │        │
  │              └─────────────────────────────────────────┘        │
  └──────────────────────────────────────────────────────────────────┘
```

## Pipeline Stages

| Stage | Module | Input | Output | Bytes |
|-------|--------|-------|--------|-------|
| 1 | `eth_parser` | Raw Ethernet frame | IP payload | Strips 14B |
| 2 | `ip_parser` | IP packet | UDP datagram | Strips 20B |
| 3 | `udp_parser` | UDP datagram | ITCH message | Strips 8B |
| 4 | `itch_decoder` | Raw ITCH bytes | Decoded struct | Decodes fields |
| 5 | `order_book` | Decoded messages | Top-of-book | Maintains state |
| 6 | `axi_lite_regs` | Book state | Register reads | SW interface |

## Supported ITCH 5.0 Messages

- **Add Order (0x41)** - New order entry
- **Order Cancel (0x58)** - Cancel existing order
- **Order Executed (0x45)** - Order filled/partially filled
- **Order Replace (0x55)** - Modify existing order

## Directory Structure

```
fpga-orderbook-engine/
├── rtl/                    # SystemVerilog source
│   ├── itch_pkg.sv         # Common types and constants
│   ├── eth_parser.sv       # Ethernet frame parser
│   ├── ip_parser.sv        # IP header parser (TODO)
│   ├── udp_parser.sv       # UDP header parser (TODO)
│   ├── itch_decoder.sv     # ITCH message decoder (TODO)
│   └── order_book.sv       # Order book engine (TODO)
├── tb/                     # Testbenches
│   └── tb_eth_parser.sv    # Ethernet parser testbench
├── sim/                    # Simulation files
│   └── test_data/          # Generated test vectors
├── scripts/                # Python utilities
│   └── gen_packets.py      # Test packet generator + reference model
├── syn/                    # Vivado synthesis project
├── docs/                   # Documentation
└── Makefile                # Build automation
```

## Quick Start

```bash
# Generate test packets
make gen

# Simulate Ethernet parser
make sim_eth
```

## Target

- **FPGA**: Xilinx 7-series (RealDigital BlackBoard / Zynq)
- **Clock**: 200 MHz target
- **Interface**: AXI-Stream (8-bit), AXI-Lite registers

## Status

- [x] Project structure and build system
- [x] Test packet generator with reference model
- [x] Ethernet parser (RTL + testbench)
- [ ] IP parser
- [ ] UDP parser
- [ ] ITCH message decoder
- [ ] Order book engine
- [ ] AXI-Lite register interface
- [ ] UVM/class-based verification
- [ ] Synthesis and timing closure
