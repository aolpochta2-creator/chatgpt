# Preserve the exact child command if an external helper fails in a CI image.
proc physical_trace_exec {command operation} {
    puts "PHYSICAL_EXEC_TRACE $command"
}
trace add execution exec enter physical_trace_exec
