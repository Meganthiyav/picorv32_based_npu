# ==============================================================================
# build_bitstream.tcl
# Automated synthesis, implementation, and bitstream generation for Vivado 2025.2
# Target: Real Digital Boolean Board (Xilinx Spartan-7 XC7S50-CSGA324-1)
# ==============================================================================

set PROJECT_NAME "PICORV_32_NPU"
set PART_NAME    "xc7s50csga324-1"

puts "=========================================================="
puts "  STARTING FPGA BUILD FOR SPARTAN-7 INT8 NPU ACCELERATOR  "
puts "  Part: $PART_NAME                                        "
puts "=========================================================="

# Create in-memory project
create_project -force -part $PART_NAME $PROJECT_NAME ./vivado_build

# Add Verilog RTL sources
add_files [list \
    ./rtl/picorv32.v \
    ./rtl/npu_mac.v \
    ./rtl/npu_controller.v \
    ./rtl/seven_seg_controller.v \
    ./rtl/picorv32_npu_top.v \
]

# Add Memory Initialization Files
add_files [list \
    ./firmware/firmware.hex \
    ./data/weights_l1.mem \
    ./data/biases_l1.mem \
    ./data/weights_l2.mem \
    ./data/biases_l2.mem \
    ./data/input_test_image.mem \
]

# Set Memory files properties
set_property file_type "Memory File" [get_files *.mem]
set_property file_type "Memory File" [get_files *.hex]

# Add XDC Constraints
add_files -fileset constrs_1 [list ./constraints/boolean_npu.xdc]

# Set Top Module
set_property top picorv32_npu_top [current_fileset]
update_compile_order -fileset sources_1

# 1. Synthesis
puts "\n[1/4] Running Synthesis..."
synth_design -top picorv32_npu_top -part $PART_NAME -directive Default
write_checkpoint -force ./vivado_build/post_synth.dcp
report_utilization -file ./vivado_build/utilization_synth.rpt
report_timing_summary -file ./vivado_build/timing_synth.rpt

# 2. Logic Optimization & Placement
puts "\n[2/4] Running Optimization & Placement..."
opt_design
place_design
write_checkpoint -force ./vivado_build/post_place.dcp

# 3. Routing
puts "\n[3/4] Running Routing & Timing Analysis..."
route_design
write_checkpoint -force ./vivado_build/post_route.dcp
report_utilization -file ./vivado_build/utilization_route.rpt
report_timing_summary -file ./vivado_build/timing_summary.rpt
report_drc -file ./vivado_build/drc_route.rpt

# 4. Generate Bitstream
puts "\n[4/4] Generating FPGA Bitstream..."
write_bitstream -force ./picorv32_npu_boolean.bit

puts "\n=========================================================="
puts "  BUILD COMPLETED SUCCESSFULLY!                           "
puts "  Generated Bitstream: ./picorv32_npu_boolean.bit         "
puts "=========================================================="
exit 0
