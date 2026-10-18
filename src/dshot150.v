/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * One-channel DShot150 transmitter.
 *
 * Default clock: 25 MHz.
 * DShot150 nominal bit period: 6.667 us.
 * At 25 MHz, the implementation rounds this to 167 clock cycles.
 * T0H is rounded to 63 cycles; T1H is 125 cycles.
 *
 * Inputs must be stable when start is asserted. start should be a one-cycle
 * pulse. A new frame is accepted only when busy is low.
 */
`default_nettype none

module dshot150 #(
    parameter integer CLK_HZ = 25_000_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [10:0] throttle_cmd,
    input  wire        telemetry,
    output reg         dshot_out,
    output reg         busy,
    output reg         done
);

    // Integer clock counts, rounded to the nearest clock cycle.
    localparam integer BIT_TICKS = (CLK_HZ + 75_000) / 150_000;
    localparam integer T0H_TICKS = (CLK_HZ + 200_000) / 400_000;
    localparam integer T1H_TICKS = (CLK_HZ + 100_000) / 200_000;

    localparam integer TIMER_WIDTH =
        (BIT_TICKS <= 2) ? 1 : $clog2(BIT_TICKS);

    wire [11:0] payload = {throttle_cmd, telemetry};
    wire [3:0] checksum =
        payload[11:8] ^ payload[7:4] ^ payload[3:0];
    wire [15:0] packet_to_send = {payload, checksum};

    reg [15:0] packet;
    reg [3:0]  bit_index;
    reg [TIMER_WIDTH-1:0] bit_timer;

    always @(posedge clk) begin
        if (!rst_n) begin
            packet    <= 16'b0;
            bit_index <= 4'd0;
            bit_timer <= {TIMER_WIDTH{1'b0}};
            dshot_out <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            // done is a one-clock pulse.
            done <= 1'b0;

            if (!busy) begin
                dshot_out <= 1'b0;
                bit_timer <= {TIMER_WIDTH{1'b0}};

                if (start) begin
                    packet    <= packet_to_send;
                    bit_index <= 4'd15;
                    bit_timer <= {TIMER_WIDTH{1'b0}};
                    dshot_out <= 1'b1;
                    busy      <= 1'b1;
                end
            end else begin
                // End the high portion of the current bit.
                if (bit_timer == ((packet[bit_index]) ?
                                  T1H_TICKS - 1 : T0H_TICKS - 1)) begin
                    dshot_out <= 1'b0;
                end

                if (bit_timer == BIT_TICKS - 1) begin
                    bit_timer <= {TIMER_WIDTH{1'b0}};

                    if (bit_index == 4'd0) begin
                        busy      <= 1'b0;
                        dshot_out <= 1'b0;
                        done      <= 1'b1;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        dshot_out <= 1'b1;
                    end
                end else begin
                    bit_timer <= bit_timer + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // These checks catch invalid timing parameters in simulation.
    initial begin
        if (CLK_HZ < 1_000_000)
            $error("dshot150: CLK_HZ is implausibly low");
        if (T0H_TICKS < 1 || T1H_TICKS >= BIT_TICKS)
            $error("dshot150: invalid pulse timing parameters");
    end
`endif

endmodule

`default_nettype wire
