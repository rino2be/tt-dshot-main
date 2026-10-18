/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout top-level wrapper for a one-channel DShot150 transmitter.
 */
`default_nettype none

module tt_um_rino2be_dshot_main (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // 11-bit DShot value is split across the dedicated and bidirectional
    // input pins. uio pins are configured as inputs in this design.
    wire [10:0] throttle_cmd = {uio_in[2:0], ui_in[7:0]};
    wire        telemetry     = uio_in[3];
    wire        start         = uio_in[4];

    wire dshot_out;
    wire busy;
    wire done;

    dshot150 #(
        .CLK_HZ(25_000_000)
    ) transmitter (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .throttle_cmd (throttle_cmd),
        .telemetry    (telemetry),
        .dshot_out    (dshot_out),
        .busy         (busy),
        .done         (done)
    );

    // Dedicated output pins:
    // uo_out[0] = DShot signal
    // uo_out[1] = busy status
    // uo_out[2] = one-cycle done pulse
    assign uo_out = {5'b0, done, busy, dshot_out};

    // All bidirectional pins are inputs.
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Keep unused template control input from producing a lint warning.
    wire _unused = &{ena, 1'b0};

endmodule

`default_nettype wire
