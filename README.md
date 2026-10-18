# Synchronous FIFO in SystemVerilog

A parameterized single-clock FIFO, verified with a class-based layered SystemVerilog testbench. The testbench uses constrained-random stimulus, a scoreboard with a queue reference model, SystemVerilog Assertions bound into the DUT, and functional coverage.

## Design (`rtl/sync_fifo.sv`)

| Parameter | Default | Meaning |
| :--- | :--- | :--- |
| `DATA_WIDTH` | 8 | Word width |
| `ADDR_WIDTH` | 4 | Address width; `DEPTH = 2**ADDR_WIDTH` (16) |

* **Full/empty detection:** the read and write pointers are `ADDR_WIDTH+1` bits wide.
  * **Empty:** the two pointers are equal.
  * **Full:** the address bits match but the MSBs differ, meaning the write pointer has wrapped once more than the read pointer.
* **Overflow and underflow protection:** a write is ignored while full, and a read is ignored while empty.
* **First-word fall-through read:** `rdata` always shows the head entry and is valid whenever `empty` is low.
* **Asynchronous active-low reset** on the pointers.

```
          +--------------------+
 wr_en -->|                    |--> rdata
 wdata -->|     sync_fifo      |--> full
 rd_en -->|  DEPTH x DATA_W    |--> empty
 clk   -->|                    |
 rst_n -->|                    |
          +--------------------+
```

## Testbench (`tb/sync_fifo_tb.sv`)

```
 generator --mailbox--> driver --> [ fifo_if ] --> DUT
                                        |            ^
                                     monitor      fifo_sva (bind)
                                        |
                                   scoreboard (queue model)
```

* **`fifo_if`:** an interface with separate driver and monitor clocking blocks, so stimulus and sampling are race-free.
* **`fifo_txn`:** randomized `wr_en`, `rd_en` and `data`.
  * The `dist` weights for `wr_en` and `rd_en` are adjustable at run time.
  * The data distribution biases toward the corner values `00` and `FF`.
* **Driver:** deliberately drives writes while full and reads while empty, to exercise the protection logic.
* **Monitor and scoreboard:** every accepted write is pushed into a queue, and every accepted read is compared against the queue head.
* **Assertions (`fifo_sva`):** bound into the DUT with `bind`. They check that:
  * the write pointer never moves while full;
  * the read pointer never moves while empty;
  * `full` and `empty` are never high at the same time;
  * occupancy never exceeds `DEPTH`;
  * `rdata` never carries X while the FIFO is not empty.

  Cover properties confirm that full, empty, and read+write-while-full were all reached.
* **Functional coverage:**
  * Crosses of write × full, read × empty, and write × read.
  * Fill-level bins: empty, low, mid, high and full.
* **Test phases:**

  | Phase | Write % | Read % | Cycles | Purpose |
  | :--- | :--- | :--- | :--- | :--- |
  | Fill | 90 | 15 | 200 | Reach full |
  | Drain | 15 | 90 | 200 | Reach empty |
  | Random | 50 | 50 | 400 | Balanced traffic |
  | Flush | 0 | 100 | 50 | Empty the FIFO |

  The test passes only if there are no scoreboard errors and the model queue is empty at the end.

### Bug injection
Compiling with `+define+INJECT_BUG` removes the overflow protection, so writes are accepted while the FIFO is full. The `a_no_wr_when_full` assertion and the scoreboard both catch it, which shows the testbench can detect a real design fault.

## Results (Synopsys VCS X-2025.06-SP1)

```
[25000] Phase 1: fill
[2025000] Phase 2: drain
[4025000] Phase 3: random
[8025000] Phase 4: flush

==================== TEST REPORT ====================
 Writes accepted   : 279
 Reads accepted    : 279
 Left in model     : 0
 Errors            : 0
 Control coverage  : 100.0%
 Fill-level cov.   : 100.0%
 RESULT: *** PASS ***
=====================================================

tb_top.dut.u_sva.c_full_hit,      852 attempts, 27 match
tb_top.dut.u_sva.c_empty_hit,     852 attempts, 32 match
tb_top.dut.u_sva.c_rw_while_full, 852 attempts, 23 match
```

* **Scoreboard:** 279 writes and 279 reads were checked, with zero mismatches, and the model was empty at the end.
* **Assertions:** none fired.
* **Functional coverage:** both covergroups reached 100%.
* **Corner cases:** every cover property was hit. The FIFO became full 27 times and empty 32 times, and saw a simultaneous read and write while full 23 times.

## Running

The testbench uses classes, mailboxes, clocking blocks, SVA and covergroups, so it needs a full SystemVerilog simulator: Questa, VCS, Xcelium, or any of them on [EDA Playground](https://www.edaplayground.com).

```bash
# Questa
vlog -sv rtl/sync_fifo.sv tb/sync_fifo_tb.sv
vsim -c tb_top -do "run -all; quit"

# Synopsys VCS
vcs -sverilog -full64 rtl/sync_fifo.sv tb/sync_fifo_tb.sv -o simv && ./simv

# Cadence Xcelium
xrun -sv rtl/sync_fifo.sv tb/sync_fifo_tb.sv

# With the planted bug, add the define, e.g.
vlog -sv +define+INJECT_BUG rtl/sync_fifo.sv tb/sync_fifo_tb.sv
```

On EDA Playground, set the top module to `tb_top`. The run writes waveforms to `dump.vcd`.

## Repository Layout
```
rtl/sync_fifo.sv     FIFO design
tb/sync_fifo_tb.sv   interface, classes, SVA module, top-level testbench
```

## License
GPL-3.0, see `LICENSE`.
