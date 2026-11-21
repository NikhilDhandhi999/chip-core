## synth/chip_core_fpga.xdc
## Xilinx Artix-7 (Digilent Arty A7-35T) Pin & 100 MHz Clock Constraints for UART SoC v7.0

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { rst }];       # BTN0
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { rx_serial }]; # USB-UART RX
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { tx_serial }]; # USB-UART TX

set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { core_done }];           # LD4
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { pred_classes_flat[0] }]; # LD5
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { pred_classes_flat[1] }]; # LD6
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { tx_busy }];             # LD7
