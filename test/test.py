# SPDX-License-Identifier: Apache-2.0
"""Cycle-level tests for the Tiny Tapeout DShot150 transmitter."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, ReadOnly, Timer


CLK_PERIOD_NS = 40
BIT_TICKS = 167
T0H_TICKS = 63
T1H_TICKS = 125


def make_packet(command: int, telemetry: int) -> int:
    payload = ((command & 0x7FF) << 1) | (telemetry & 1)
    checksum = ((payload >> 8) ^ (payload >> 4) ^ payload) & 0xF
    return (payload << 4) | checksum


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_one_dshot_frame(dut):
    """Check packet bits, pulse widths, busy, and done."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    command = 0x123
    telemetry = 1
    packet = make_packet(command, telemetry)

    dut.ui_in.value = command & 0xFF
    dut.uio_in.value = ((command >> 8) & 0x7) | (telemetry << 3)

    # Start is a one-cycle pulse.
    await FallingEdge(dut.clk)
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 4)
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert (int(dut.uo_out.value) & 0b010) != 0, "busy should assert on start"
    await FallingEdge(dut.clk)
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 4)

    # Capture all 16 bit cells, including the first sample at the start edge.
    samples = [int(dut.uo_out.value) & 1]
    for _ in range(16 * BIT_TICKS - 1):
        await RisingEdge(dut.clk)
        await ReadOnly()
        samples.append(int(dut.uo_out.value) & 1)

    # Check MSB-first order and each bit's high-time.
    for bit_number in range(16):
        bit_value = (packet >> (15 - bit_number)) & 1
        start = bit_number * BIT_TICKS
        expected_high = T1H_TICKS if bit_value else T0H_TICKS
        high_count = sum(samples[start:start + BIT_TICKS])
        assert high_count == expected_high, (
            f"bit {bit_number} expected {bit_value}, "
            f"high cycles {high_count}, expected {expected_high}"
        )
        assert all(v == 0 for v in samples[start + expected_high:start + BIT_TICKS]), (
            f"bit {bit_number} should remain low after its high pulse"
        )

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert (int(dut.uo_out.value) & 0b010) == 0, "busy should clear after frame"
    assert (int(dut.uo_out.value) & 0b100) != 0, "done should pulse after frame"
    assert (int(dut.uo_out.value) & 0b001) == 0, "output should return low"


@cocotb.test()
async def test_reset_and_idle(dut):
    """Check idle output and reset behavior."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    assert int(dut.uo_out.value) == 0
    await ClockCycles(dut.clk, 10)
    assert int(dut.uo_out.value) == 0
