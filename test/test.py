import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# ──────────────────────────────────────────────────────────────────────────────
# REFERENCE MODEL (Golden Vector Generator for the BMS ASIC)
# This perfectly mimics the 4-Tap FIR math and Sparsity Gating of the Verilog.
# ──────────────────────────────────────────────────────────────────────────────
class BMSModel:
    def __init__(self):
        # 4-Tap Pipeline [t-3, t-2, t-1, t-0]
        self.window = [0, 0, 0, 0]
        self.mode = 0 # 0 = Radiography, 1 = Thermal

    def reset(self):
        self.window = [0, 0, 0, 0]

    def set_mode(self, mode):
        self.mode = int(mode)

    def push_data(self, val):
        # Sparsity Gating: The hardware ignores perfect 0s
        if val != 0:
            self.window.pop(0)       # Drop oldest frame
            self.window.append(val)  # Append newest frame (t-0)

    def get_expected_trigger(self):
        # Grab weights and thresholds based on mode
        if self.mode == 0:
            # Radiography Mode (X-Ray flicker)
            weights = [69, -127, 63, -118]
            threshold = -12000
        else:
            # Thermal Mode (Ejecta Heat)
            weights = [111, 11, 127, 99]
            threshold = 97

        # Multiply-Accumulate (MAC)
        mac_sum = sum(w * d for w, d in zip(weights, self.window))

        # Hardware trigger fires if sum exceeds threshold
        return 1 if mac_sum > threshold else 0


# ──────────────────────────────────────────────────────────────────────────────
# TEST SUITE
# ──────────────────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_bms_golden_vectors(dut):
    dut._log.info("Starting Dual-Mode BMS ASIC Test")
    
    # Initialize software reference model
    model = BMSModel()

    # Set the clock period (10 MHz = 100ns)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Ensure all inputs are zeroed out initially
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # ─────────────────────────────────────────────
    # PHASE 1: RADIOGRAPHY MODE TEST
    # ─────────────────────────────────────────────
    dut._log.info("--- TESTING RADIOGRAPHY MODE ---")
    
    # Reset Sequence
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    model.reset()
    model.set_mode(0)
    dut.uio_in.value = 0 # Switch to Radiography mode
    await ClockCycles(dut.clk, 2)

    # Simulated X-Ray Brightness Data
    rad_sequence = [
        150, 151, 150, 149, 150, # Stable frames (should not trigger)
        80, 70, 60               # Sudden dark drop due to venting (should trigger)
    ]

    for val in rad_sequence:
        dut.ui_in.value = val
        model.push_data(val)
        await ClockCycles(dut.clk, 1) # Wait 1 clock cycle for processing
        await FallingEdge(dut.clk)
        
        expected_trigger = model.get_expected_trigger()
        # The hardware trigger is uo_out bit 0
        actual_trigger = int(dut.uo_out.value) & 0b1
        
        dut._log.info(f"Input: {val:3d} | Expected Trigger: {expected_trigger} | Hardware Trigger: {actual_trigger}")
        assert actual_trigger == expected_trigger, f"Mismatch in Radiography Mode! Input {val}"

    # ─────────────────────────────────────────────
    # PHASE 2: THERMAL MODE TEST
    # ─────────────────────────────────────────────
    dut._log.info("--- TESTING THERMAL MODE ---")
    
    # Reset Sequence
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    model.reset()
    model.set_mode(1)
    dut.uio_in.value = 1 # Switch to Thermal mode
    await ClockCycles(dut.clk, 2)

    # Simulated FTRC Heat Generation Data
    therm_sequence = [
        5, 4, 6, 5, 5,   # Low baseline heat (should not trigger)
        35, 40, 45       # Massive thermal spike (should trigger)
    ]

    for val in therm_sequence:
        dut.ui_in.value = val
        model.push_data(val)
        await ClockCycles(dut.clk, 1) # Wait 1 clock cycle for processing
        await FallingEdge(dut.clk)
        
        expected_trigger = model.get_expected_trigger()
        actual_trigger = int(dut.uo_out.value) & 0b1
        
        dut._log.info(f"Input: {val:3d} | Expected Trigger: {expected_trigger} | Hardware Trigger: {actual_trigger}")
        assert actual_trigger == expected_trigger, f"Mismatch in Thermal Mode! Input {val}"

    dut._log.info("All Golden Vector Tests Passed! Silicon perfectly matches AI.")
