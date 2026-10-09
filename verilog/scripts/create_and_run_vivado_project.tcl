# ==============================================================================
# create_and_run_vivado_project.tcl
# Builds a complete Vivado project with all sources, runs synthesis,
# runs implementation through bitstream generation, and readies it for GUI.
# ==============================================================================

set PROJECT_NAME "PICORV_32_NPU"
set PART_NAME    "xc7s50csga324-1"

puts "=========================================================="
puts "  CREATING VIVADO PROJECT: $PROJECT_NAME                  "
puts "  TARGET PART:             $PART_NAME                     "
puts "=========================================================="

# Create project in current directory
create_project -force $PROJECT_NAME . -part $PART_NAME

# Set project properties
set_property default_lib xil_defaultlib [current_project]
set_property target_language Verilog [current_project]

# 1. Add RTL Sources
puts "\n--> Adding Verilog RTL Sources..."
add_files -fileset sources_1 [list \
    ./rtl/picorv32.v \
    ./rtl/npu_mac.v \
    ./rtl/npu_controller.v \
    ./rtl/seven_seg_controller.v \
    ./rtl/picorv32_npu_top.v \
]

# 2. Add Memory Initialization Files (.mem and .hex)
puts "--> Adding Memory Initialization Files..."
add_files -fileset sources_1 [list \
    ./firmware/firmware.hex \
    ./data/weights_l1.mem \
    ./data/biases_l1.mem \
    ./data/weights_l2.mem \
    ./data/biases_l2.mem \
    ./data/input_test_image.mem \
    ./data/test_img_digit_0.mem \
    ./data/test_img_digit_1.mem \
    ./data/test_img_digit_2.mem \
    ./data/test_img_digit_3.mem \
    ./data/test_img_digit_4.mem \
    ./data/test_img_digit_5.mem \
    ./data/test_img_digit_6.mem \
    ./data/test_img_digit_7.mem \
    ./data/test_img_digit_8.mem \
    ./data/test_img_digit_9.mem \
]

set_property file_type "Memory File" [get_files *.mem]
set_property file_type "Memory File" [get_files *.hex]

# 3. Add Physical XDC Constraints
puts "--> Adding XDC Constraints..."
add_files -fileset constrs_1 [list ./constraints/boolean_npu.xdc]

# 4. Add Simulation Testbenches
puts "--> Adding Simulation Testbenches..."
add_files -fileset sim_1 [list \
    ./sim/tb_npu.v \
    ./sim/tb_picorv32_npu.v \
]
set_property top tb_picorv32_npu [get_filesets sim_1]

# Set Top Module for Synthesis
set_property top picorv32_npu_top [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n=========================================================="
puts "  LAUNCHING SYNTHESIS (synth_1)...                        "
puts "=========================================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed! Check synth_1 run log."
    exit 1
}
puts "--> Synthesis completed successfully!"

puts "\n=========================================================="
puts "  LAUNCHING IMPLEMENTATION & BITSTREAM (impl_1)...        "
puts "=========================================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed! Check impl_1 run log."
    exit 1
}
puts "--> Implementation and bitstream completed successfully!"

puts "\n=========================================================="
puts "  PROJECT BUILD COMPLETE!                                 "
puts "  Project File: [pwd]/$PROJECT_NAME.xpr                   "
puts "=========================================================="
exit 0
