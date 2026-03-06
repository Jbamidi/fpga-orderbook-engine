# =============================================================================
# Makefile - FPGA Order Book Engine
# =============================================================================
# Quick reference:
#   make gen       - Generate test packets (Python)
#   make sim_eth   - Simulate Ethernet parser
#   make clean     - Clean generated files
# =============================================================================

# Tools (adjust paths for your system)
PYTHON     ?= python3
IVERILOG   ?= iverilog
VVP        ?= vvp
VIVADO     ?= vivado

# Directories
RTL_DIR    = rtl
TB_DIR     = tb
SIM_DIR    = sim
SCRIPT_DIR = scripts
SYN_DIR    = syn

# Common RTL files
PKG_FILES  = $(RTL_DIR)/itch_pkg.sv

# =============================================================================
# Test Data Generation
# =============================================================================
.PHONY: gen
gen:
	@echo "=== Generating test packets ==="
	$(PYTHON) $(SCRIPT_DIR)/gen_packets.py
	@echo ""

# =============================================================================
# Ethernet Parser Simulation
# =============================================================================
.PHONY: sim_eth
sim_eth: gen
	@echo "=== Simulating Ethernet Parser ==="
	@mkdir -p $(SIM_DIR)/build
	$(IVERILOG) -g2012 -o $(SIM_DIR)/build/tb_eth_parser \
		$(PKG_FILES) \
		$(RTL_DIR)/eth_parser.sv \
		$(TB_DIR)/tb_eth_parser.sv
	cd $(SIM_DIR) && $(VVP) build/tb_eth_parser
	@echo ""

# =============================================================================
# IP Parser Simulation (Phase 3)
# =============================================================================
# .PHONY: sim_ip
# sim_ip: gen
# 	@echo "=== Simulating IP Parser ==="
# 	...

# =============================================================================
# Full Pipeline Simulation (Phase 4+)
# =============================================================================
# .PHONY: sim_full
# sim_full: gen
# 	...

# =============================================================================
# Synthesis (Phase 8)
# =============================================================================
# .PHONY: synth
# synth:
# 	...

# =============================================================================
# Clean
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(SIM_DIR)/build
	rm -rf $(SIM_DIR)/test_data
	rm -rf *.vcd

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  gen       - Generate test packets from Python"
	@echo "  sim_eth   - Simulate Ethernet parser"
	@echo "  clean     - Remove generated files"
	@echo "  help      - Show this help"
