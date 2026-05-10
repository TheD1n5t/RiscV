# Run from the repository root with:
# vivado -mode batch -source scripts/synth_resource_variants.tcl

set part_name xczu3eg-sbva484-1-i
set repo_root [file normalize [file join [file dirname [info script]] ..]]
cd $repo_root

set src_dir   RiscVTest.srcs/sources_1/new
set out_dir   resource_reports

file mkdir $out_dir

set sources [list \
  $src_dir/alu.vhd \
  $src_dir/fault_injector.vhd \
  $src_dir/tmr_fault_voter.vhd \
  $src_dir/decoder.vhd \
  $src_dir/regfile.vhd \
  $src_dir/csr_file.vhd \
  $src_dir/load_store_unit.vhd \
  $src_dir/cpu.vhd \
  $src_dir/dmem.vhd \
  $src_dir/imem_dp_ram.vhd \
  $src_dir/uart_rx.vhd \
  $src_dir/uart_tx.vhd \
  $src_dir/simple_timer.vhd \
  $src_dir/riscv_soc_boot.vhd \
  $src_dir/riscv_soc_boot_top.vhd \
]

set variants {
  {baseline     {G_PC_TMR=false G_STATE_TMR=false G_RF_TMR=false G_RF_SELF_HEAL=false G_IMEM_ECC=false G_DMEM_ECC=false G_FAULT_INJECT=false}}
  {pc_state_tmr {G_PC_TMR=true  G_STATE_TMR=true  G_RF_TMR=false G_RF_SELF_HEAL=false G_IMEM_ECC=false G_DMEM_ECC=false G_FAULT_INJECT=false}}
  {rf_tmr       {G_PC_TMR=true  G_STATE_TMR=true  G_RF_TMR=true  G_RF_SELF_HEAL=false G_IMEM_ECC=false G_DMEM_ECC=false G_FAULT_INJECT=false}}
  {rf_self_heal {G_PC_TMR=true  G_STATE_TMR=true  G_RF_TMR=true  G_RF_SELF_HEAL=true  G_IMEM_ECC=false G_DMEM_ECC=false G_FAULT_INJECT=false}}
  {mem_ecc      {G_PC_TMR=true  G_STATE_TMR=true  G_RF_TMR=true  G_RF_SELF_HEAL=true  G_IMEM_ECC=true  G_DMEM_ECC=true  G_FAULT_INJECT=false}}
  {full_fi      {G_PC_TMR=true  G_STATE_TMR=true  G_RF_TMR=true  G_RF_SELF_HEAL=true  G_IMEM_ECC=true  G_DMEM_ECC=true  G_FAULT_INJECT=true}}
}

foreach variant $variants {
  set name     [lindex $variant 0]
  set generics [lindex $variant 1]

  puts "Synthesizing $name"
  create_project -in_memory -part $part_name
  foreach src $sources {
    read_vhdl -vhdl2008 $src
  }
  synth_design -top riscv_soc_boot_top -part $part_name -generic $generics
  report_utilization -file $out_dir/${name}_utilization_synth.rpt
  report_timing_summary -file $out_dir/${name}_timing_synth.rpt
  write_checkpoint -force $out_dir/${name}_synth.dcp
  close_project
}
