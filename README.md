# Parameterized Synchronous FIFO in SystemVerilog

A single-clock FIFO (first-in, first-out buffer) with full/empty flags and overflow/underflow protection, verified with a self-checking SystemVerilog testbench.

## Design (`rtl/sync_fifo.sv`)

| Parameter | Default | Meaning |
| :--- | :--- | :--- |
| `DATA_WIDTH` | 8 | Word width |
| `ADDR_WIDTH` | 4 | Address width; `DEPTH = 2**ADDR_WIDTH` (16) |

```
          +--------------------+
 wr_en -->|                    |--> rdata
 wdata -->|     sync_fifo      |--> full
 rd_en -->|  DEPTH x DATA_W    |--> empty
 clk   -->|                    |
 rst_n -->|                    |
          +--------------------+
```

* **Full/empty detection:** the read and write pointers have one extra bit.
  * **Empty:** the two pointers are equal.
  * **Full:** the address bits match but the extra bit differs, meaning the write pointer has wrapped once more than the read pointer.
* **Overflow protection:** a write is ignored while the FIFO is full.
* **Underflow protection:** a read is ignored while the FIFO is empty.
* **First-word fall-through:** `rdata` always shows the oldest entry whenever `empty` is low.
* **Asynchronous active-low reset** on the pointers.

## Testbench (`tb/sync_fifo_tb_simple.sv`)

The testbench checks itself and prints PASS or FAIL, so you don't need to read waveforms to know the result.

* **Stimulus:** one task, `cycle(write, read, data)`, drives the inputs on the falling clock edge. Each test is a loop of `cycle(...)` calls.
* **Reference model:** a SystemVerilog queue holds what the FIFO *should* contain. Every accepted write is pushed into it, and every accepted read is compared against its oldest entry.
* **Flag checks:** `check_flags()` compares `full` and `empty` with the size of the reference model.
* **Assertions:**
  * `full` and `empty` are never high at the same time.
  * A write while full does not move the write pointer.

### Tests

| # | Test | What it checks |
| :--- | :--- | :--- |
| 1 | Fill | Write 16 entries, `full` goes high |
| 2 | Overflow | A write while full is ignored |
| 3 | Drain | Read 16 entries in the correct order, `empty` goes high |
| 4 | Underflow | A read while empty is ignored |
| 5 | Simultaneous read/write | Level stays the same, data stays in order |
| 6 | Random traffic | 300 cycles of random reads and writes, then drain and check every byte |

### Bug injection

Compiling with `+define+INJECT_BUG` removes the overflow protection, so writes are accepted while the FIFO is full. The testbench then reports data mismatches, flag errors and assertion failures, which shows it really catches design bugs.

## Results (Synopsys VCS X-2025.06-SP1)

```
Test 1: fill the FIFO
Test 2: write while full (overflow)
Test 3: drain the FIFO
Test 4: read while empty (underflow)
Test 5: simultaneous read and write
Test 6: random reads and writes

========== TEST REPORT ==========
 Writes accepted : 199
 Reads accepted  : 199
 Errors          : 0
 RESULT: *** PASS ***
=================================
```

Every written byte was read back in the correct order, the flags always matched the model, and no assertion fired. The exact transfer count changes from run to run because Test 6 uses random values.

## Running

**EDA Playground:** paste `rtl/sync_fifo.sv` into the Design tab and `tb/sync_fifo_tb_simple.sv` into the Testbench tab, choose a SystemVerilog simulator (e.g. Synopsys VCS), set the top module to `tb_top`, and click Run.

**Command line:**

```bash
# Synopsys VCS
vcs -sverilog -full64 rtl/sync_fifo.sv tb/sync_fifo_tb_simple.sv -o simv && ./simv

# Questa
vlog -sv rtl/sync_fifo.sv tb/sync_fifo_tb_simple.sv
vsim -c tb_top -do "run -all; quit"

# Verilator (free)
verilator --binary --timing --assert -Wno-fatal --top-module tb_top rtl/sync_fifo.sv tb/sync_fifo_tb_simple.sv && ./obj_dir/Vtb_top

# With the planted bug, add the define, e.g.
vcs -sverilog -full64 +define+INJECT_BUG rtl/sync_fifo.sv tb/sync_fifo_tb_simple.sv -o simv && ./simv
```

The run writes waveforms to `dump.vcd`.

## Repository Layout

```
rtl/sync_fifo.sv            FIFO design
tb/sync_fifo_tb_simple.sv   self-checking testbench
```

## License

GPL-3.0, see `LICENSE`.
