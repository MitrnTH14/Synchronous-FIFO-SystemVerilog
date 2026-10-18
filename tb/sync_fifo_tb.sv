`timescale 1ns/1ps
// ============================================================
// Class-based SystemVerilog testbench for sync_fifo
//  generator -> mailbox -> driver -> DUT -> monitor -> scoreboard
//  + SVA (bound into the DUT) + functional coverage
// ============================================================

// ---------------- INTERFACE ----------------
interface fifo_if (input logic clk);
  logic       rst_n;
  logic       wr_en, rd_en, full, empty;
  logic [7:0] wdata, rdata;

  // driver: sample just before the edge, drive 1ns after it
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output wr_en, rd_en, wdata;
    input  full, empty;
  endclocking

  // monitor: inputs only
  clocking mon_cb @(posedge clk);
    default input #1step;
    input wr_en, rd_en, wdata, rdata, full, empty;
  endclocking
endinterface

// ---------------- CONFIG ----------------
// The test changes these to create fill / drain / random phases
class fifo_cfg;
  int unsigned wr_pct = 50;
  int unsigned rd_pct = 50;
  bit          done   = 0;
endclass

// ---------------- TRANSACTION ----------------
class fifo_txn;
  rand bit       wr_en;
  rand bit       rd_en;
  rand bit [7:0] data;
  int unsigned   wr_pct = 50;
  int unsigned   rd_pct = 50;

  constraint c_wr   { wr_en dist {1 := wr_pct, 0 := (100 - wr_pct)}; }
  constraint c_rd   { rd_en dist {1 := rd_pct, 0 := (100 - rd_pct)}; }
  constraint c_data { data  dist {8'h00 := 10, 8'hFF := 10, [8'h01:8'hFE] :/ 80}; }
endclass

// ---------------- GENERATOR ----------------
class generator;
  mailbox #(fifo_txn) mbx;
  fifo_cfg            cfg;

  function new(mailbox #(fifo_txn) mbx, fifo_cfg cfg);
    this.mbx = mbx;
    this.cfg = cfg;
  endfunction

  task run();
    fifo_txn t;
    while (!cfg.done) begin
      t = new();
      t.wr_pct = cfg.wr_pct;
      t.rd_pct = cfg.rd_pct;
      if (!t.randomize()) $fatal(1, "Randomization failed");
      mbx.put(t);              // mailbox size 1 keeps generator in step with driver
    end
  endtask
endclass

// ---------------- DRIVER ----------------
class driver;
  virtual fifo_if     vif;
  mailbox #(fifo_txn) mbx;

  function new(virtual fifo_if vif, mailbox #(fifo_txn) mbx);
    this.vif = vif;
    this.mbx = mbx;
  endfunction

  // Drives wr_en/rd_en even when full/empty on purpose -> tests protection logic
  task run();
    fifo_txn t;
    forever begin
      mbx.get(t);
      @(vif.drv_cb);
      vif.drv_cb.wr_en <= t.wr_en;
      vif.drv_cb.rd_en <= t.rd_en;
      vif.drv_cb.wdata <= t.data;
    end
  endtask
endclass

// ---------------- SCOREBOARD ----------------
class scoreboard;
  bit [7:0]    model_q[$];            // reference model = a queue
  int unsigned n_wr, n_rd, n_err;

  covergroup level_cg with function sample(int lvl);
    cp_level : coverpoint lvl {
      bins empty = {0};
      bins low   = {[1:5]};
      bins mid   = {[6:10]};
      bins high  = {[11:15]};
      bins full  = {16};
    }
  endgroup

  function new();
    level_cg = new();
  endfunction

  function void write(bit [7:0] d);
    model_q.push_back(d);
    n_wr++;
  endfunction

  function void read(bit [7:0] d);
    bit [7:0] exp;
    if (model_q.size() == 0) begin
      n_err++;
      $error("[SB] Read accepted while model is empty at %0t", $time);
      return;
    end
    exp = model_q.pop_front();
    n_rd++;
    if (d !== exp) begin
      n_err++;
      $error("[SB] MISMATCH at %0t: expected %h, got %h", $time, exp, d);
    end
  endfunction

  function void sample_level();
    level_cg.sample(model_q.size());
  endfunction
endclass

// ---------------- MONITOR ----------------
class monitor;
  virtual fifo_if vif;
  scoreboard      sb;

  covergroup ctrl_cg with function sample(bit wr, bit rd, bit full, bit empty);
    cp_wr    : coverpoint wr;
    cp_rd    : coverpoint rd;
    cp_full  : coverpoint full;
    cp_empty : coverpoint empty;
    x_wr_full  : cross cp_wr, cp_full;    // includes write attempted while full
    x_rd_empty : cross cp_rd, cp_empty;   // includes read attempted while empty
    x_wr_rd    : cross cp_wr, cp_rd;      // includes simultaneous read + write
  endgroup

  function new(virtual fifo_if vif, scoreboard sb);
    this.vif = vif;
    this.sb  = sb;
    ctrl_cg  = new();
  endfunction

  task run();
    forever begin
      @(vif.mon_cb);
      ctrl_cg.sample(vif.mon_cb.wr_en, vif.mon_cb.rd_en,
                     vif.mon_cb.full,  vif.mon_cb.empty);
      // read first: rdata belongs to the entry at the head before this edge
      if (vif.mon_cb.rd_en && !vif.mon_cb.empty) sb.read(vif.mon_cb.rdata);
      if (vif.mon_cb.wr_en && !vif.mon_cb.full)  sb.write(vif.mon_cb.wdata);
      sb.sample_level();
    end
  endtask
endclass

// ---------------- ENVIRONMENT ----------------
class environment;
  fifo_cfg            cfg;
  mailbox #(fifo_txn) mbx;
  generator           gen;
  driver              drv;
  monitor             mon;
  scoreboard          sb;

  function new(virtual fifo_if vif);
    cfg = new();
    mbx = new(1);
    sb  = new();
    gen = new(mbx, cfg);
    drv = new(vif, mbx);
    mon = new(vif, sb);
  endfunction

  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
    join_none
  endtask

  function void report();
    $display("\n==================== TEST REPORT ====================");
    $display(" Writes accepted   : %0d", sb.n_wr);
    $display(" Reads accepted    : %0d", sb.n_rd);
    $display(" Left in model     : %0d", sb.model_q.size());
    $display(" Errors            : %0d", sb.n_err);
    $display(" Control coverage  : %0.1f%%", mon.ctrl_cg.get_coverage());
    $display(" Fill-level cov.   : %0.1f%%", sb.level_cg.get_coverage());
    if (sb.n_err == 0 && sb.model_q.size() == 0) $display(" RESULT: *** PASS ***");
    else                                         $display(" RESULT: *** FAIL ***");
    $display("=====================================================\n");
  endfunction
endclass

// ---------------- ASSERTIONS (bound into DUT) ----------------
module fifo_sva #(parameter int DATA_WIDTH = 8, parameter int ADDR_WIDTH = 4) (
  input logic                  clk, rst_n, wr_en, rd_en, full, empty,
  input logic [ADDR_WIDTH:0]   wptr, rptr,
  input logic [DATA_WIDTH-1:0] rdata
);
  localparam int DEPTH = 1 << ADDR_WIDTH;

  logic [ADDR_WIDTH:0] occ;
  assign occ = wptr - rptr;               // kept at pointer width so wrap-around works

  // Overflow protection: write pointer must not move while full
  a_no_wr_when_full: assert property (@(posedge clk) disable iff (!rst_n)
    full |=> $stable(wptr))
    else $error("[SVA] Write pointer moved while FULL");

  // Underflow protection: read pointer must not move while empty
  a_no_rd_when_empty: assert property (@(posedge clk) disable iff (!rst_n)
    empty |=> $stable(rptr))
    else $error("[SVA] Read pointer moved while EMPTY");

  // FIFO can never be full and empty at the same time
  a_not_full_and_empty: assert property (@(posedge clk) disable iff (!rst_n)
    !(full && empty))
    else $error("[SVA] FULL and EMPTY both high");

  // Occupancy can never exceed DEPTH
  a_occupancy: assert property (@(posedge clk) disable iff (!rst_n)
    occ <= DEPTH)
    else $error("[SVA] Occupancy %0d exceeds DEPTH", occ);

  // Valid data whenever FIFO is not empty
  a_no_x_rdata: assert property (@(posedge clk) disable iff (!rst_n)
    !empty |-> !$isunknown(rdata))
    else $error("[SVA] X on rdata while not empty");

  // Did the test actually reach the corner cases?
  c_full_hit:      cover property (@(posedge clk) disable iff (!rst_n) $rose(full));
  c_empty_hit:     cover property (@(posedge clk) disable iff (!rst_n) $rose(empty));
  c_rw_while_full: cover property (@(posedge clk) disable iff (!rst_n) full && wr_en && rd_en);
endmodule

// ---------------- TOP ----------------
module tb_top;
  logic clk = 0;
  always #5 clk = ~clk;                   // 100 MHz

  fifo_if vif (clk);

  sync_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) dut (
    .clk   (clk),
    .rst_n (vif.rst_n),
    .wr_en (vif.wr_en),
    .wdata (vif.wdata),
    .rd_en (vif.rd_en),
    .rdata (vif.rdata),
    .full  (vif.full),
    .empty (vif.empty)
  );

  bind sync_fifo fifo_sva #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sva (.*);

  environment env;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0);   // full dump: VCS cannot selectively dump interfaces
  end

  initial begin
    env = new(vif);

    // reset
    vif.rst_n = 0;
    vif.wr_en = 0; vif.rd_en = 0; vif.wdata = 0;
    repeat (3) @(posedge clk);
    vif.rst_n = 1;

    env.run();

    // Phase 1: FILL   - write-heavy, should hit FULL
    $display("[%0t] Phase 1: fill", $time);
    env.cfg.wr_pct = 90; env.cfg.rd_pct = 15;
    repeat (200) @(posedge clk);

    // Phase 2: DRAIN  - read-heavy, should hit EMPTY
    $display("[%0t] Phase 2: drain", $time);
    env.cfg.wr_pct = 15; env.cfg.rd_pct = 90;
    repeat (200) @(posedge clk);

    // Phase 3: RANDOM - balanced traffic
    $display("[%0t] Phase 3: random", $time);
    env.cfg.wr_pct = 50; env.cfg.rd_pct = 50;
    repeat (400) @(posedge clk);

    // Phase 4: FLUSH  - stop writing, read everything out
    $display("[%0t] Phase 4: flush", $time);
    env.cfg.wr_pct = 0; env.cfg.rd_pct = 100;
    repeat (50) @(posedge clk);

    env.cfg.done = 1;
    env.report();
    $finish;
  end
endmodule
