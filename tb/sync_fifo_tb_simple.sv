`timescale 1ns/1ps
// ============================================================
// Simple self-checking testbench for sync_fifo
//
//  How it works:
//   1. Tasks drive the FIFO inputs on the falling clock edge.
//   2. A queue called "model" acts as the expected FIFO.
//      Every accepted write is pushed into it; every accepted
//      read is compared against the front of it.
//   3. Flags (full/empty) are checked against the model size.
//   4. Two assertions catch illegal states automatically.
//   5. At the end it prints PASS or FAIL.
// ============================================================
module tb_top;

  // ---------------- clock and signals ----------------
  logic       clk = 0;
  always #5 clk = ~clk;              // 100 MHz clock

  logic       rst_n;
  logic       wr_en, rd_en;
  logic [7:0] wdata, rdata;
  logic       full, empty;

  localparam int DEPTH = 16;         // 2**ADDR_WIDTH

  // ---------------- DUT ----------------
  sync_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wdata(wdata),
    .rd_en(rd_en), .rdata(rdata),
    .full(full),   .empty(empty)
  );

  // ---------------- reference model ----------------
  logic [7:0] model[$];              // queue = what the FIFO should hold
  int         errors = 0;
  int         n_wr = 0, n_rd = 0;

  // Count and print an error
  task automatic report_error(input string msg);
    errors++;
    $display("%s (time %0t)", msg, $time);
  endtask

  // On every rising edge, update the model exactly like the FIFO should
  always @(posedge clk) begin
    if (rst_n) begin
      // read first: rdata shows the oldest entry before this edge
      if (rd_en && !empty) begin
        if (rdata !== model[0]) begin
          errors++;
          $display("ERROR at %0t: read %h, expected %h", $time, rdata, model[0]);
        end
        void'(model.pop_front());
        n_rd++;
      end
      if (wr_en && !full) begin
        model.push_back(wdata);
        n_wr++;
      end
    end
  end

  // ---------------- assertions ----------------
  // FIFO can never be full and empty at the same time
  a_not_full_and_empty: assert property (@(posedge clk) disable iff (!rst_n)
    !(full && empty))
    else report_error("ASSERT: full and empty both high");

  // A write while full must be ignored (write pointer must not move)
  a_no_overflow: assert property (@(posedge clk) disable iff (!rst_n)
    full |=> $stable(dut.wptr))
    else report_error("ASSERT: write accepted while full");

  // ---------------- helper tasks ----------------
  // One clock cycle of stimulus: drive inputs on the falling edge
  task automatic cycle(input logic w, input logic r, input logic [7:0] d);
    @(negedge clk);
    wr_en = w;
    rd_en = r;
    wdata = d;
  endtask

  // Compare full/empty flags with the model size
  task automatic check_flags();
    @(negedge clk);
    wr_en = 0; rd_en = 0;
    if (full  !== (model.size() == DEPTH)) begin
      errors++; $display("ERROR at %0t: full=%b, model holds %0d", $time, full, model.size());
    end
    if (empty !== (model.size() == 0)) begin
      errors++; $display("ERROR at %0t: empty=%b, model holds %0d", $time, empty, model.size());
    end
  endtask

  // ---------------- test sequence ----------------
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);

    // Reset
    rst_n = 0; wr_en = 0; rd_en = 0; wdata = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // Test 1: write until full
    $display("Test 1: fill the FIFO");
    for (int i = 0; i < DEPTH; i++) cycle(1, 0, i + 8'h10);
    check_flags();                               // expect full = 1

    // Test 2: write while full must be ignored
    $display("Test 2: write while full (overflow)");
    cycle(1, 0, 8'hAA);
    check_flags();                               // still exactly 16 entries

    // Test 3: read until empty
    $display("Test 3: drain the FIFO");
    for (int i = 0; i < DEPTH; i++) cycle(0, 1, 8'h00);
    check_flags();                               // expect empty = 1

    // Test 4: read while empty must be ignored
    $display("Test 4: read while empty (underflow)");
    cycle(0, 1, 8'h00);
    check_flags();                               // still empty

    // Test 5: read and write in the same cycle
    $display("Test 5: simultaneous read and write");
    for (int i = 0; i < 8; i++)  cycle(1, 0, 8'h50 + i);    // half fill
    for (int i = 0; i < 20; i++) cycle(1, 1, 8'hC0 + i);    // level stays the same
    check_flags();

    // Test 6: random traffic
    $display("Test 6: random reads and writes");
    repeat (300) cycle($urandom_range(0, 1), $urandom_range(0, 1), $urandom);
    check_flags();

    // Empty the FIFO so every written byte gets checked
    while (!empty) cycle(0, 1, 8'h00);
    check_flags();

    // ---------------- report ----------------
    $display("\n========== TEST REPORT ==========");
    $display(" Writes accepted : %0d", n_wr);
    $display(" Reads accepted  : %0d", n_rd);
    $display(" Errors          : %0d", errors);
    if (errors == 0 && model.size() == 0) $display(" RESULT: *** PASS ***");
    else                                  $display(" RESULT: *** FAIL ***");
    $display("=================================\n");
    $finish;
  end

endmodule
