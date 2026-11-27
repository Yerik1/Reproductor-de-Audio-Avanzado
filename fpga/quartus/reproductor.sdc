create_clock -name CLOCK_50  -period 20.000 [get_ports CLOCK_50]
create_clock -name CLOCK3_50 -period 20.000 [get_ports CLOCK3_50]
derive_pll_clocks
derive_clock_uncertainty
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
