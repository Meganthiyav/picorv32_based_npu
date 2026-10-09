# ==============================================================================
# program_board.tcl
# Automatically connects to the Real Digital Spartan-7 Boolean board via JTAG
# and programs picorv32_npu_boolean.bit
# ==============================================================================

puts "=========================================================="
puts "  CONNECTING TO SPARTAN-7 BOOLEAN BOARD HARDWARE SERVER   "
puts "=========================================================="

open_hw_manager
connect_hw_server -allow_non_jtag

set hw_targets [get_hw_targets]
puts "Available HW Targets: $hw_targets"

if {[llength $hw_targets] == 0} {
    puts "ERROR: No JTAG targets found. Please check board power and USB cable."
    exit 1
}

# Open the first hardware target (Boolean board FTDI JTAG)
open_hw_target [lindex $hw_targets 0]

set hw_device [lindex [get_hw_devices] 0]
puts "Selected HW Device: $hw_device"

current_hw_device $hw_device
refresh_hw_device -update_hw_probes false $hw_device

# Set bitstream file
set bitfile "./picorv32_npu_boolean.bit"
puts "Programming bitstream: $bitfile ..."
set_property PROGRAM.FILE $bitfile $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device

puts "=========================================================="
puts "  BOARD PROGRAMMED SUCCESSFULLY!                          "
puts "=========================================================="
exit 0
