{
thermal_warning: ($t | contains("No thermal warning level has been recorded") | not),
performance_warning: ($t | contains("No performance warning level has been recorded") | not)}
