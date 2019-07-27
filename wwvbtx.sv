`default_nettype none
`timescale 1ns/1ps

module wwvbtx #(
  parameter CLOCK_PERIOD=100_000_000
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
  // simple arithmetic yields 60kHz with an error of 0.04% 
  // (100MHz / 60kHz = 1666 and 2/3). If that's not accurate enough,
  // can round up to 1667 (error: 0.02%) or dither with alternate 1666/1667
  // (error: 0.01%).
  localparam CARRIER_CLOCK_PERIOD = CLOCK_PERIOD / 60_000;


  // modulation
  
  // time-code frame: 60 bits, of which 42 are variable (the rest are frame
  // reference, position marker and reserved).
  
  // avalon write/read interface logic
endmodule

`default_nettype wire
