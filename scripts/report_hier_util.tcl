# Run from the repository root with:
# vivado -mode batch -source scripts/report_hier_util.tcl

set repo_root [file normalize [file join [file dirname [info script]] ..]]
cd $repo_root

foreach dcp [glob -nocomplain resource_reports/*_synth.dcp] {
  set base [file rootname [file tail $dcp]]
  set name [string map {_synth ""} $base]
  puts "Reporting hierarchy for $name"
  open_checkpoint $dcp
  report_utilization -hierarchical -file resource_reports/${name}_utilization_hier.rpt
  close_design
}
