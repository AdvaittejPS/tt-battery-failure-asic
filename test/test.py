import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

class BMSModel:
    def __init__(self):
        self.window = [0, 0, 0, 0]
        self.mode = 0 
    def reset(self):
        self.window = [0, 0, 0, 0]
    def push(self, val):
        if val != 0:
            self.window.pop(0)
            self.window.append(val)
    def expected(self):
        if self.window[0] == 0: return 0
        if self.mode == 0:
            w, t = [69, -127, 63, -118], -12000
        else:
            w, t = [111, 11, 127, 99], 24765
        res = sum(wi * di for wi, di in zip(w, self.window))
        return 1 if res > t else 0

@cocotb.test()
async def test_bms_golden_vectors(dut):
    model = BMSModel()
    # 10us period matches the Tiny Tapeout Template exactly
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Test Sequence
    for mode in [0, 1]:
        dut._log.info(f"Testing Mode {mode}")
        model.mode = mode
        dut.uio_in.value = mode
        await ClockCycles(dut.clk, 5)
        
        data = [150, 150, 150, 150, 150, 80, 70, 60] if mode == 0 else [5, 5, 5, 5, 5, 100, 120, 140]
        history = [0, 0]
        
        for val in data:
            dut.ui_in.value = val
            model.push(val)
            history.append(model.expected())
            exp = history.pop(0)
            await ClockCycles(dut.clk, 1)
            await FallingEdge(dut.clk)
            assert (int(dut.uo_out.value) & 1) == exp
            
        # Flush delay
        for _ in range(2):
            history.append(model.expected())
            exp = history.pop(0)
            await ClockCycles(dut.clk, 1)
            await FallingEdge(dut.clk)
            assert (int(dut.uo_out.value) & 1) == exp

    dut._log.info("Final Verification Passed!")
    await ClockCycles(dut.clk, 20)
