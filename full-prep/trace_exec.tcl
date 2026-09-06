# Preserve exact child commands if an external helper fails in the pinned image.
proc full_prep_trace_exec {command operation} {
    puts "FULL_PREP_EXEC_TRACE $command"
}
trace add execution exec enter full_prep_trace_exec
