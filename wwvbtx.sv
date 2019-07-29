`default_nettype none
`timescale 1ns/1ps

module bitcell #(parameter bit RESET_VALUE='0)
(
  input wire clk,
  input wire clken,
  input wire reset,

  input wire sel,
  input wire d_in0,
  input wire d_in1,
  output reg d_out)
);
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      d_out <= RESET_VALUE;
    end
    else begin
      if (clken) begin
        d_out <= sel ? d_in1 : d_in0;
      end
    end
  end
endmodule

typedef enum {CELL_ZERO=2'b00, CELL_ONE=2'b01, CELL_REF=2'b10} t_cell_value;

module timeframe_cell #(parameter t_cell_value RESET_VALUE = CELL_REF)
(
  input wire clk,
  input wire clken,
  input wire reset,

  input wire sel,
  input t_cell_value d_in0,
  input t_cell_value d_in1,
  output t_cell_value d_out
);

  genvar i;
  for (i = 0; i < 2; ++i) begin: cellgen
    bitcell #(.RESET_VALUE(RESET_VALUE[i])) the_bit(
      .clk (clk),
      .clken (clken),
      .reset (reset),
      .sel (sel),
      .d_in0 (d_in0[i]),
      .d_in1 (d_in1[i]),
      .d_out (d_out[i])
  end
endmodule

module timeframe #(parameter t_cell_value RESET_VALUE[0:59])
(
  input wire clk,
  input wire clken,
  input wire reset,

  input t_cell_value load_data[0:59],
  input wire load,

  output t_cell_value current
);

  // 60 timeframe_cells make up a timeframe.
  // arbitrarily, element 0 is the "head" cell,
  // giving the current second's cell value.
  // cells are serially connected: cell0 takes cell1's
  // output,  cell1 takes cell2's, ... up to cell 59 which
  // takes cell0's output.
  t_cell_value shift_data[0:59];
  assign current = shift_data[0];
  genvar i;
  for (i = 0; i < 60; ++i) begin
    timeframe_cell #(.RESET_VALUE(RESET_VALUE[i])) the_cell(
      .clk (clk),
      .clken (clken),
      .reset (reset),
      .sel (load),
      .d_in0 (shift_data[i < 59 ? i + 1 : 0]),
      .d_in1 (load_data[i]),
      .d_out (shift_data[i])
    );
  end

endmodule

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
  //   In each second, power is reduced, and then restored after 200,
  //   500 or 800ms.
  //     0bit: power restored after 200ms
  //     1bit: power restored after 500ms
  //     refbit: power restored after 800ms
  //   A particular second's action is stored in a
  //   A time frame is stored in 60 storage cells, which can be shifted
  //   serially or loaded in parallel. The head of the shift chain is the
  //   "current" second.
  // some work to do here: fill in the various indices of load_data with
  // constant values (for ref, position marker), or register values from the
  // CSRs.
  t_cell_value load_data[0:59] = {
    CELL_REF,                        //  0  frame reference bit P_r
    csr0[ 6] ? CELL_ONE : CELL_ZERO, //  1  minutes, 40
    csr0[ 5] ? CELL_ONE : CELL_ZERO, //  2  minutes, 20
    csr0[ 4] ? CELL_ONE : CELL_ZERO, //  3  minutes, 10
    CELL_ZERO,                       //  4  reserved
    csr0[ 3] ? CELL_ONE : CELL_ZERO, //  5  minutes, 8
    csr0[ 2] ? CELL_ONE : CELL_ZERO, //  6  minutes, 4
    csr0[ 1] ? CELL_ONE : CELL_ZERO, //  7  minutes, 2
    csr0[ 0] ? CELL_ONE : CELL_ZERO, //  8  minutes, 1
    CELL_REF ,                       //  9  position marker P_1
    CELL_ZERO,                       // 10  reserved
    CELL_ZERO,                       // 11  reserved
    csr0[13] ? CELL_ONE : CELL_ZERO, // 12  hours, 20
    csr0[12] ? CELL_ONE : CELL_ZERO, // 13  hours, 10
    CELL_ZERO,                       // 14  reserved
    csr0[11] ? CELL_ONE : CELL_ZERO, // 15  hours, 8
    csr0[10] ? CELL_ONE : CELL_ZERO, // 16  hours, 4
    csr0[ 9] ? CELL_ONE : CELL_ZERO, // 17  hours, 2
    csr0[ 8] ? CELL_ONE : CELL_ZERO, // 18  hours, 1
    CELL_REF ,                       // 19  position marker P_2
    CELL_ZERO,                       // 20  reserved
    CELL_ZERO,                       // 21  reserved
    csr0[25] ? CELL_ONE : CELL_ZERO, // 22  day of year, 200
    csr0[24] ? CELL_ONE : CELL_ZERO, // 23  day of year, 100
    CELL_ZERO,                       // 24  reserved
    csr0[23] ? CELL_ONE : CELL_ZERO, // 25  day of year, 80
    csr0[22] ? CELL_ONE : CELL_ZERO, // 26  day of year, 40
    csr0[21] ? CELL_ONE : CELL_ZERO, // 27  day of year, 20
    csr0[20] ? CELL_ONE : CELL_ZERO, // 28  day of year, 10
    CELL_REF ,                       // 29  position marker P_3
    csr0[19] ? CELL_ONE : CELL_ZERO, // 30  day of year, 8
    csr0[18] ? CELL_ONE : CELL_ZERO, // 31  day of year, 4
    csr0[17] ? CELL_ONE : CELL_ZERO, // 32  day of year, 2
    csr0[16] ? CELL_ONE : CELL_ZERO, // 33  day of year, 1
    CELL_ZERO,                       // 34  reserved
    CELL_ZERO,                       // 35  reserved
    csr1[22] ? CELL_ONE : CELL_ZERO, // 36  UTIsign, +
    csr1[21] ? CELL_ONE : CELL_ZERO, // 37  UTIsign, -
    csr1[20] ? CELL_ONE : CELL_ZERO, // 38  UTIsign, +
    CELL_REF ,                       // 39  position marker P_4
    csr1[19] ? CELL_ONE : CELL_ZERO, // 40  UTI correction, 0.8s
    csr1[18] ? CELL_ONE : CELL_ZERO, // 41  UTI correction, 0.4s
    csr1[17] ? CELL_ONE : CELL_ZERO, // 42  UTI correction, 0.2s
    csr1[16] ? CELL_ONE : CELL_ZERO, // 43  UTI correction, 0.1s
    CELL_ZERO,                       // 44  reserved
    csr1[15] ? CELL_ONE : CELL_ZERO, // 45  year, 80
    csr1[14] ? CELL_ONE : CELL_ZERO, // 46  year, 40
    csr1[13] ? CELL_ONE : CELL_ZERO, // 47  year, 20
    csr1[12] ? CELL_ONE : CELL_ZERO, // 48  year, 10
    CELL_REF ,                       // 49  position marker P_5
    csr1[11] ? CELL_ONE : CELL_ZERO, // 50  year, 8
    csr1[10] ? CELL_ONE : CELL_ZERO, // 51  year, 4
    csr1[ 9] ? CELL_ONE : CELL_ZERO, // 52  year, 2
    csr1[ 8] ? CELL_ONE : CELL_ZERO, // 53  year, 1
    CELL_REF ,                       // 54  reserved
    csr1[ 5] ? CELL_ONE : CELL_ZERO, // 55  leap year indicator
    csr1[ 4] ? CELL_ONE : CELL_ZERO, // 56  leap second warning
    csr1[ 1] ? CELL_ONE : CELL_ZERO, // 57  daylight saving time
    csr1[ 0] ? CELL_ONE : CELL_ZERO, // 58  daylight saving time
    CELL_REF                         // 59  frame reference bit P_0
  };
  timeframe #(
      .RESET_VALUE({
        CELL_REF,  //  0  frame reference bit P_r
        CELL_ZERO, //  1  minutes, 40
        CELL_ZERO, //  2  minutes, 20
        CELL_ZERO, //  3  minutes, 10
        CELL_ZERO, //  4  reserved
        CELL_ZERO, //  5  minutes, 8
        CELL_ZERO, //  6  minutes, 4
        CELL_ZERO, //  7  minutes, 2
        CELL_ZERO, //  8  minutes, 1
        CELL_REF , //  9  position marker P_1
        CELL_ZERO, // 10  reserved
        CELL_ZERO, // 11  reserved
        CELL_ZERO, // 12  hours, 20
        CELL_ZERO, // 13  hours, 10
        CELL_ZERO, // 14  reserved
        CELL_ZERO, // 15  hours, 8
        CELL_ZERO, // 16  hours, 4
        CELL_ZERO, // 17  hours, 2
        CELL_ZERO, // 18  hours, 1
        CELL_REF , // 19  position marker P_2
        CELL_ZERO, // 20  reserved
        CELL_ZERO, // 21  reserved
        CELL_ZERO, // 22  day of year, 200
        CELL_ZERO, // 23  day of year, 100
        CELL_ZERO, // 24  reserved
        CELL_ZERO, // 25  day of year, 80
        CELL_ZERO, // 26  day of year, 40
        CELL_ZERO, // 27  day of year, 20
        CELL_ZERO, // 28  day of year, 10
        CELL_REF , // 29  position marker P_3
        CELL_ZERO, // 30  day of year, 8
        CELL_ZERO, // 31  day of year, 4
        CELL_ZERO, // 32  day of year, 2
        CELL_ZERO, // 33  day of year, 1
        CELL_ZERO, // 34  reserved
        CELL_ZERO, // 35  reserved
        CELL_ZERO, // 36  UTIsign, +
        CELL_ZERO, // 37  UTIsign, -
        CELL_ZERO, // 38  UTIsign, +
        CELL_REF , // 39  position marker P_4
        CELL_ZERO, // 40  UTI correction, 0.8s
        CELL_ZERO, // 41  UTI correction, 0.4s
        CELL_ZERO, // 42  UTI correction, 0.2s
        CELL_ZERO, // 43  UTI correction, 0.1s
        CELL_ZERO, // 44  reserved
        CELL_ZERO, // 45  year, 80
        CELL_ZERO, // 46  year, 40
        CELL_ZERO, // 47  year, 20
        CELL_ZERO, // 48  year, 10
        CELL_REF , // 49  position marker P_5
        CELL_ZERO, // 50  year, 8
        CELL_ZERO, // 51  year, 4
        CELL_ZERO, // 52  year, 2
        CELL_ZERO, // 53  year, 1
        CELL_ZERO, // 54  reserved
        CELL_ZERO, // 55  leap year indicator
        CELL_ZERO, // 56  leap second warning
        CELL_ZERO, // 57  daylight saving time
        CELL_ZERO, // 58  daylight saving time
        CELL_REF   // 59  frame reference bit P_0
      })
    )
    the_timeframe(
      .clk (clk),
      .clken (clk_1Hz),
      .reset (reset),

      .load_data (load_data),
      .load (load),

      .current (current)
  );

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
  // time data can be grouped as 13 nibbles:
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

  // 'X': unused bit, set to 0
  // '.': set to 0 or 1
  //
  // |       dayofyear       |     hours     |   minutes     |
  // |   d2  |   d1  |   d0  |  d1   |  d0   |  d1   |  d0   |
  // |3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|
  // |X|X|.|.|.|.|.|.|.|.|.|.|X|X|.|.|.|.|.|.|X|.|.|.|.|.|.|.|
  // +-------------------------------------------------------+
  // |2|2|2|2|2|2|2|2|1|1|1|1|1|1|1|1|1|1|0|0|0|0|0|0|0|0|0|0|
  // |7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
  reg [31:0] csr0;

  // |       |       |       |      year     |       |       |
  // |       |u_sign |u_corr |  d1   |  d0   | leap  |  dst  |
  // |3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|3|2|1|0|
  // |X|X|X|X|X|.|.|.|.|.|.|.|.|.|.|.|.|.|.|.|X|X|.|.|X|X|.|.|
  // +-------------------------------------------------------+
  // |2|2|2|2|2|2|2|2|1|1|1|1|1|1|1|1|1|1|0|0|0|0|0|0|0|0|0|0|
  // |7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
  reg [31:0] csr1;

  // avalon write/read interface logic
endmodule

`default_nettype wire
