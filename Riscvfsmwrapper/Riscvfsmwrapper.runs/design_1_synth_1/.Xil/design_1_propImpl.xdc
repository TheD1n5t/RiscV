set_property SRC_FILE_INFO {cfile:d:/Documents/FAU/NanoSat/riscv_radhart_coll/RiscVFSM/Riscvfsmwrapper/Riscvfsmwrapper.gen/sources_1/bd/design_1/ip/design_1_rst_ps8_0_99M_0/design_1_rst_ps8_0_99M_0.xdc rfile:../../../Riscvfsmwrapper.gen/sources_1/bd/design_1/ip/design_1_rst_ps8_0_99M_0/design_1_rst_ps8_0_99M_0.xdc id:1 order:EARLY scoped_inst:rst_ps8_0_99M/U0} [current_design]
set_property SRC_FILE_INFO {cfile:d:/Documents/FAU/NanoSat/riscv_radhart_coll/RiscVFSM/Riscvfsmwrapper/Riscvfsmwrapper.gen/sources_1/bd/design_1/ip/design_1_riscv_soc_axi_wrapper_0_1/src/cpu.xdc rfile:../../../Riscvfsmwrapper.gen/sources_1/bd/design_1/ip/design_1_riscv_soc_axi_wrapper_0_1/src/cpu.xdc id:2 order:EARLY scoped_inst:riscv_soc_axi_wrapper_0/U0} [current_design]
current_instance rst_ps8_0_99M/U0
set_property src_info {type:SCOPED_XDC file:1 line:50 export:INPUT save:INPUT read:READ} [current_design]
create_waiver -type CDC -id {CDC-11} -user "proc_sys_reset" -desc "Timing uncritical paths" -tags "1171415" -scope -internal -to [get_pins -quiet -filter REF_PIN_NAME=~*D -of_objects [get_cells -hierarchical -filter {NAME =~ */ACTIVE_LOW_AUX.ACT_LO_AUX/GENERATE_LEVEL_P_S_CDC.SINGLE_BIT.CROSS_PLEVEL_IN2SCNDRY_IN_cdc_to}]]
current_instance
current_instance riscv_soc_axi_wrapper_0/U0
set_property src_info {type:SCOPED_XDC file:2 line:2 export:INPUT save:INPUT read:READ} [current_design]
set_property PACKAGE_PIN W5 [get_ports clk]
set_property src_info {type:SCOPED_XDC file:2 line:3 export:INPUT save:INPUT read:READ} [current_design]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property src_info {type:SCOPED_XDC file:2 line:6 export:INPUT save:INPUT read:READ} [current_design]
create_clock -name sys_clk -period 10.000 [get_ports clk]
