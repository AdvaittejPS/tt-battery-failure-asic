import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# REFERENCE MODEL
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
        if self.window[0] == 0: return 0
        if self.mode == 0:
            weights, threshold = [69, -127, 63, -118], -12000
        else:
            weights, threshold = [111, 11, 127, 99], 24765
        mac_sum = sum(w * d for w, d in zip(weights, self.window))
        return 1 if mac_sum > threshold else 0

async def feed_and_check(dut, model, sequence):
    history = [0, 0] # Delay for 2-cycle synchronizer
    for val in sequence:
        dut.ui_in.value = val
        model.push_data(val)
        history.append(model.get_expected_trigger())
        current_expected = history.pop(0)
        await ClockCycles(dut.clk, 1)
        await FallingEdge(dut.clk)
        assert (int(dut.uo_out.value) & 1) == current_expected

    # Flush the 2-cycle delay at the end
    for _ in range(2):
        history.append(model.get_expected_trigger())
        current_expected = history.pop(0)
        await ClockCycles(dut.clk, 1)
        await FallingEdge(dut.clk)
        assert (int(dut.uo_out.value) & 1) == current_expected

@cocotb.test()
async def test_bms_golden_vectors(dut):
    dut._log.info("Starting BMS ASIC Test")
    model = BMSModel()
    
    # Matching your template's 10us clock (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Test Radiography
    dut._log.info("Testing Radiography Mode")
    model.set_mode(0)
    dut.uio_in.value = 0
    await feed_and_check(dut, model, [150, 150, 150, 150, 150, 80, 70, 60])

    # Test Thermal
    dut._log.info("Testing Thermal Mode")
    model.set_mode(1)
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 5) # Let mode sync
    await feed_and_check(dut, model, [5, 5, 5, 5, 5, 100, 120, 140])

    dut._log.info("All Golden Vector Tests Passed!")
    await ClockCycles(dut.clk, 10)
