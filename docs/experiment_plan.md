# RiscVFSM Experiment Plan

## Positioning

This project should not be framed as a new selective-TMR method for full RISC-V soft processors. That is too close to Cora et al., "Selective hardening of RISCV soft-processors for space applications" (Microelectronics Reliability, 2025).

The more accurate contribution is:

> This work evaluates a compact VHDL RISC-V soft core that combines local TMR for control/state/register paths with SECDED-style ECC for instruction and data memories. Faults are injected directly at architectural storage points in simulation, allowing a transparent evaluation of masking, correction, uncorrectable detection, failures, and timeouts.

## Difference To Cora et al. 2025

| Aspect | Cora et al. 2025 | This project |
|---|---|---|
| Processor | NEORV32 | compact in-house VHDL RISC-V core |
| Main technique | selective module-level TMR | mixed local TMR plus memory ECC |
| Granularity | processor modules | PC, FSM state, register file, IMEM, DMEM |
| Fault injection | FPGA configuration memory via SEM-IP/PyXEL flow | VHDL-level injection into selected architectural storage |
| Goal | identify vulnerable NEORV32 modules and selectively harden them | show a simple, reproducible protection scheme for a small NanoSat-oriented core |
| Evaluation output | reliability vs area/performance for full/partial TMR | outcome classes: masked, corrected, uncorrectable, failure, timeout |

## Protected Elements In The Current Design

| Element | Protection | Relevant files |
|---|---|---|
| Program counter | TMR with majority voter | `cpu.vhd`, `tmr_fault_voter.vhd` |
| CPU state/FSM | TMR with majority voter | `cpu.vhd`, `tmr_fault_voter.vhd` |
| Register file | three banks with majority-voted reads, optional self-heal | `regfile.vhd` |
| Data memory | 39-bit codeword, single-error correction, double-error detection | `dmem.vhd` |
| Instruction memory | 39-bit codeword, single-error correction, double-error detection | `imem_dp_ram.vhd` |
| Fault model hook | XOR mask on selected target when strobe is active | `fault_injector.vhd` |

## Campaign Structure

Use `tb_fault_campaign.vhd` as the central experiment.

Run classes:

| Domain | Injected element | Expected interpretation |
|---|---|---|
| `REF` | no fault | validates the expected store trace |
| `PC` / `PC-RND` | one TMR PC replica | should be corrected by voting |
| `STATE` / `ST-RND` | one TMR FSM-state replica | should be corrected by voting |
| `RF` / `RF-RND` | one register-file bank | should be corrected by voting, optionally repaired by self-heal |
| `DMEM` / `DM-RND` | one DMEM ECC codeword bit | single-bit faults should correct; some unused/unread faults may be masked |
| `IMEM` / `IM-RND` | one IMEM ECC codeword bit | single-bit faults should correct; unused/unreached faults may be masked |
| `IMEM2` | two IMEM bits | should be detected as uncorrectable |

Outcome classes:

| Outcome | Meaning |
|---|---|
| `MASKED` | fault had no visible effect on the checked program output |
| `CORRECTED` | TMR/ECC error flag was observed and program output remained correct |
| `UNCORRECTABLE` | double-error flag was observed, but the checked run still reached the expected stores |
| `FAILURE` | store address/data trace differed from the expected reference |
| `TIMEOUT` | program did not complete within the campaign cycle budget |

## Current Example Result

The latest observed campaign log reports:

```text
FAULT CAMPAIGN SUMMARY: total=19 injected=18 masked=7 corrected=11 uncorrectable=1 failures=0 timeouts=0
```

This result is useful as a smoke result, but it is too small for the final thesis evaluation. For the final table, run larger campaigns such as 100, 500, or 1000 injected runs and report percentages per domain.

## Minimum Final Evaluation

Recommended final tables:

1. Functional campaign summary per protection domain:

| Domain | Runs | Masked | Corrected | Uncorrectable | Failures | Timeouts |
|---|---:|---:|---:|---:|---:|---:|
| PC | | | | | | |
| FSM state | | | | | | |
| Register file | | | | | | |
| DMEM | | | | | | |
| IMEM | | | | | | |

2. Resource comparison:

| Variant | LUT | FF | BRAM | Fmax | Notes |
|---|---:|---:|---:|---:|---|
| Baseline | | | | | no TMR/ECC |
| Protected | | | | | current design |
| Optional full replication | | | | | only if implemented or estimated clearly |

3. Claim table:

| Claim | Evidence |
|---|---|
| Local TMR protects control-path faults | PC/FSM campaign results |
| ECC protects memory storage faults | IMEM/DMEM single-bit campaign results |
| Multi-bit faults are detected but not corrected | IMEM2 / double-bit results |
| The approach is transparent and reproducible | VHDL-level fault injector and campaign testbench |

## Thesis Text Snippet

Unlike previous work that identifies vulnerable modules of a complete NEORV32 processor and applies selective TMR at module level, this work focuses on a compact RISC-V soft core with locally protected architectural state. The design combines TMR for the program counter, control FSM state, and register file with SECDED-style ECC for instruction and data memories. This allows the effect of faults in specific architectural storage elements to be evaluated directly in simulation and classified as masked, corrected, detected but uncorrectable, failure, or timeout.
