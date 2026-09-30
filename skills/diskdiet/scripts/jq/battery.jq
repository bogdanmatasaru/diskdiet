[.SPPowerDataType[] | select(._name == "spbattery_information") | .sppower_battery_health_info
| {cycle_count: .sppower_battery_cycle_count,
   condition: .sppower_battery_health,
   max_capacity_pct: ((.sppower_battery_health_maximum_capacity | tostring | rtrimstr("%") | tonumber?) // null)}]
| .[0]
