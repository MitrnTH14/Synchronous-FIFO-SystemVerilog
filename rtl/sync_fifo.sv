`timescale 1ns/1ps
// ============================================================
// Parameterized Synchronous FIFO
//  - Single clock for read and write
//  - Pointers are ADDR_WIDTH+1 bits: extra MSB distinguishes FULL from EMPTY
//  - First-word-fall-through read: rdata is valid whenever !empty
//  - Compile with +define+INJECT_BUG to plant an overflow bug
// ============================================================
module sync_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int ADDR_WIDTH = 4            // DEPTH = 2**ADDR_WIDTH
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  wr_en,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic                  rd_en,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic                  full,
  output logic                  empty
);
  localparam int DEPTH = 1 << ADDR_WIDTH;

  logic [DATA_WIDTH-1:0] mem [DEPTH];
  logic [ADDR_WIDTH:0]   wptr, rptr;
  logic                  wr_ok, rd_ok;

`ifdef INJECT_BUG
  assign wr_ok = wr_en;                   // BUG: write is NOT blocked when full
`else
  assign wr_ok = wr_en && !full;          // overflow protection
`endif
  assign rd_ok = rd_en && !empty;         // underflow protection

  // pointer update
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr <= '0;
      rptr <= '0;
    end else begin
      if (wr_ok) wptr <= wptr + 1'b1;
      if (rd_ok) rptr <= rptr + 1'b1;
    end
  end

  // memory write
  always_ff @(posedge clk)
    if (wr_ok) mem[wptr[ADDR_WIDTH-1:0]] <= wdata;

  // EMPTY: pointers fully equal
  // FULL : same address, but write pointer has wrapped one extra time (MSB differs)
  assign empty = (wptr == rptr);
  assign full  = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) &&
                 (wptr[ADDR_WIDTH-1:0] == rptr[ADDR_WIDTH-1:0]);

  // read data (combinational)
  assign rdata = mem[rptr[ADDR_WIDTH-1:0]];

endmodule
