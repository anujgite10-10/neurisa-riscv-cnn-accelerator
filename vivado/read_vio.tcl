# ================================================================================
# NeurISA — VIO UART Decode Script
# ================================================================================
# Run in Vivado Hardware Manager TCL console after programming the FPGA:
#   source vivado/read_vio.tcl
# Reads the VIO debug probes and decodes the last 16 UART bytes as ASCII text.
# ================================================================================

proc read_neurisa_vio {} {
    # Refresh VIO probes
    refresh_hw_vio [get_hw_vios]

    # Read probe values
    set uart_buf   [get_property INPUT_VALUE [get_hw_probes probe_in0 -of_objects [get_hw_vios]]]
    set gpio_out   [get_property INPUT_VALUE [get_hw_probes probe_in1 -of_objects [get_hw_vios]]]
    set byte_cnt   [get_property INPUT_VALUE [get_hw_probes probe_in2 -of_objects [get_hw_vios]]]
    set mmcm_lock  [get_property INPUT_VALUE [get_hw_probes probe_in3 -of_objects [get_hw_vios]]]

    puts ""
    puts "=========================================="
    puts " NeurISA VIO Debug Monitor"
    puts "=========================================="
    puts " MMCM Locked : $mmcm_lock"
    puts " GPIO Output : $gpio_out"
    puts " Bytes Recv  : $byte_cnt"
    puts "=========================================="

    # Decode UART buffer as ASCII
    # uart_buf is 128 bits = 16 bytes, hex string
    puts " Last 16 UART bytes (hex): $uart_buf"
    puts ""
    puts " Decoded text: "

    # Convert hex to ASCII
    set hex_str [string map {_ ""} $uart_buf]
    set text ""
    for {set i 0} {$i < [string length $hex_str]} {incr i 2} {
        set hex_byte [string range $hex_str $i [expr {$i+1}]]
        set dec_val [scan $hex_byte %x]
        if {$dec_val >= 32 && $dec_val <= 126} {
            append text [format %c $dec_val]
        } elseif {$dec_val == 10} {
            append text "\\n"
        } elseif {$dec_val == 13} {
            append text "\\r"
        } else {
            append text "."
        }
    }
    puts "  \"$text\""
    puts "=========================================="
    puts ""
}

# Auto-poll: read VIO every 2 seconds for 30 seconds
proc monitor_neurisa {{duration 30} {interval 2}} {
    puts "Monitoring NeurISA VIO for $duration seconds..."
    set end_time [expr {[clock seconds] + $duration}]
    while {[clock seconds] < $end_time} {
        read_neurisa_vio
        after [expr {$interval * 1000}]
    }
    puts "Monitoring complete."
}

puts ""
puts "NeurISA VIO decode script loaded."
puts "Commands:"
puts "  read_neurisa_vio        - Read once"
puts "  monitor_neurisa 30 2    - Monitor for 30s, poll every 2s"
puts ""

# Auto-read once on load
read_neurisa_vio
