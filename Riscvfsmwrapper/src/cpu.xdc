## Clock pin (Beispiel-Pin!)
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

## 50 MHz -> Period = 20 ns
create_clock -name sys_clk -period 10.000 [get_ports clk]
