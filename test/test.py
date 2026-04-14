import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# ──────────────────────────────────────────────────────────────────────────────
# REFERENCE MODEL (Golden Vector Generator for the BMS ASIC)
# ──────────────────────────────────────────────────────────────────────────────
class BMSModel:
    def __init__(self):
        self.window = [0, 0, 0, 0]
        self.mode = 0 

    def reset(self):
        self.window = [0, 0, 0, 0]

    def set_mode(self, mode):
        self.mode = int(mode)

    def push_data(self, val):
        if val != 0:
            self.window.pop(0)       
            self.window.append(val)  

    def get_expected_trigger(self):
        if self.window[0] == 0:
            return 0

        if self.mode == 0:
            weights = [69, -127, 63, -118]
            threshold = -12000
        else:
            weights = [111, 11, 127, 99]
            threshold = 24765

        mac_sum = sum(w * d for w, d in zip(weights, self.window))
        return 1 if mac_sum > threshold else 0

async def feed_and_check(dut, model, sequence):
    history = [0, 0] 
    
    for val in sequence:
        dut.ui_in.value = val
        model.push_data(val)
        
        future_expected = model.get_expected_trigger()
        history.append(future_expected)
        current_expected = history.pop(0)
        
        await ClockCycles(dut.clk, 1)
        await FallingEdge(dut.clk)
        
        actual_trigger = int(dut.uo_out.value) & 0b1
        dut._log.info(f"Input: {val:3d} | Expected: {current_expected} | Hardware: {actual_trigger}")
        assert actual_trigger == current_expected, f"Mismatch at input {val}!"

    for _ in range(2):
        last_val = sequence[-1]
        dut.ui_in.value = last_val
        model.push_data(last_val)
        
        history.append(model.get_expected_trigger())
        current_expected = history.pop(0)
        
        await ClockCycles(dut.clk, 1)
        await FallingEdge(dut.clk)
        
        actual_trigger = int(dut.uo_out.value) & 0b1
        dut._log.info(f"FLUSH: {last_val:3d} | Expected: {current_expected} | Hardware: {actual_trigger}")
        assert actual_trigger == current_expected, "Mismatch during pipeline flush!"

# ──────────────────────────────────────────────────────────────────────────────
# TEST SUITE
# ──────────────────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_bms_golden_vectors(dut):
    dut._log.info("Starting Dual-Mode BMS ASIC Test")
    
    model = BMSModel()
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    dut._log.info("--- TESTING RADIOGRAPHY MODE ---")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    model.reset()
    model.set_mode(0)
    dut.uio_in.value = 0 
    await ClockCycles(dut.clk, 2)

    rad_sequence = [150, 150, 150, 150, 150, 80, 70, 60]
    await feed_and_check(dut, model, rad_sequence)

    dut._log.info("--- TESTING THERMAL MODE ---")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    model.reset()
    model.set_mode(1)
    dut.uio_in.value = 1 
    await ClockCycles(dut.clk, 2)

    therm_sequence = [5, 5, 5, 5, 5, 100, 120, 140]
    await feed_and_check(dut, model, therm_sequence)

    dut._log.info("All Golden Vector Tests Passed! Silicon perfectly matches AI.")
    
    # ─────────────────────────────────────────────────────────
    # TEARDOWN FLUSH (Prevents Simulator Crash on Exit)
    # ─────────────────────────────────────────────────────────
    dut._log.info("Flushing logic gates to zero before simulator shutdown...")
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 20)
