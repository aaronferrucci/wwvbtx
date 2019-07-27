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

  // time-code frame: 60 bits, of which 42 are variable; the rest are frame
  // reference, position marker and reserved.
  // "The carrier power is reduced 10 dB at the start of each second. If
  // full power is restored 200 ms later, it represents a 0 bit. If full
  // power is restored 500 ms later, it represents a 1 bit. If full power
  // is restored 800 ms later, it represents a reference marker or a
  // position identifier."
  //
  // list of bits, in order of transmission:
  //  0  frame reference bit P_r
  //  1  minutes, 40
  //  2  minutes, 20
  //  3  minutes, 10
  //  4  reserved
  //  5  minutes, 8
  //  6  minutes, 4
  //  7  minutes, 2
  //  8  minutes, 1
  //  9  position marker P_1
  // 10  reserved
  // 11  reserved
  // 12  hours, 20
  // 13  hours, 10
  // 14  reserved
  // 15  hours, 8
  // 16  hours, 4
  // 17  hours, 2
  // 18  hours, 1
  // 19  position marker P_2
  // 20  reserved
  // 21  reserved
  // 22  day of year, 200
  // 23  day of year, 100
  // 24  reserved
  // 25  day of year, 80
  // 26  day of year, 40
  // 27  day of year, 20
  // 28  day of year, 10
  // 29  position marker P_3
  // 30  day of year, 8
  // 31  day of year, 4
  // 32  day of year, 2
  // 33  day of year, 1
  // 34  reserved
  // 35  reserved
  // 36  UTIsign, +
  // 37  UTIsign, -
  // 38  UTIsign, +
  // 39  position marker P_4
  // 40  UTI correction, 0.8s
  // 41  UTI correction, 0.4s
  // 42  UTI correction, 0.2s
  // 43  UTI correction, 0.1s
  // 44  reserved
  // 45  year, 80
  // 46  year, 40
  // 47  year, 20
  // 48  year, 10
  // 49  position marker P_5
  // 50  year, 8
  // 51  year, 4
  // 52  year, 2
  // 53  year, 1
  // 54  reserved
  // 55  leap year indicator
  // 56  leap second warning
  // 57  daylight saving time
  // 58  daylight saving time
  // 59  frame reference bit P_0
  //

  // mapping between variable time frame bits and
  // CSRs:
  // time data can be grouped as 12 nibbles:
  // minutes_d1 (3 bits)
  // minutes_d0 (4 bits)
  // hours_d1 (2 bits)
  // hours_d0 (4 bits)
  // dayofyear_d2 (2 bits)
  // dayofyear_d1 (4 bits)
  // dayofyear_d0 (4 bits)

  // uti_sign (3 bits)
  // uti_correction (4 bits)
  // year_d1 (4 bits)
  // year_d0 (4 bits)
  // leap_year (2 bits)
  // daylight_saving_time (2 bits)

  // avalon write/read interface logic
endmodule

`default_nettype wire
