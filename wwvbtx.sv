`default_nettype none
`timescale 1ns/1ps

module carrier_clk_gen #(
  parameter CLK_PERIOD=100_000_000
)
(
  input wire clk,
  input wire reset,

  output reg carrier_clk

);
  // Carrier frequency generation
  // simple arithmetic yields 60kHz with an error of 0.04%
  // (100MHz / 60kHz = 1666 and 2/3). If that's not accurate enough,
  // can round up to 1667 (error: 0.02%) or dither with alternate 1666/1667
  // (error: 0.01%).
  localparam CARRIER_CLK_PERIOD = CLK_PERIOD / 60_000;
  localparam CARRIER_CLK_HALF_PERIOD = CARRIER_CLK_PERIOD / 2;
  localparam CARRIER_COUNTER_WIDTH = $clog2(CARRIER_CLK_HALF_PERIOD);
  reg [CARRIER_COUNTER_WIDTH - 1 : 0] carrier_clk_counter = '0;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      carrier_clk <= '0;
      carrier_clk_counter <= '0;
    end
    else begin
      if (carrier_clk_counter >= CARRIER_CLK_HALF_PERIOD - 1) begin
        carrier_clk_counter <= '0;
        carrier_clk <= ~carrier_clk;
      end
      else begin
        carrier_clk_counter <= carrier_clk_counter + 1'b1;
      end
    end
  end
endmodule

module wwvbtx #(
  parameter CLK_PERIOD=100_000_000
)
(
  // clock/reset interfaces
  input wire clk,
  input wire reset,

  // avalon slave interface
  // fixed read latency: 1
  input wire write,
  input wire read,
  input wire [3:0] byteenable,
  input wire [31:0] writedata,
  output wire [31:0] readdata,
  input wire address,

  // conduit for the output signal
  output wire wwvb
);

  // ref: https://tf.nist.gov/general/pdf/1383.pdf

  // Carrier frequency generation
  wire carrier_clk;
  carrier_clk_gen the_carrier_clk(
    .clk (clk),
    .reset (reset),
    .carrier_clk (carrier_clk)
  );
  // modulation

  // time-code frame: 60 bits, of which 42 are variable (the rest are frame
  // reference, position marker and reserved).

  // avalon write/read interface logic
endmodule

`default_nettype wire
