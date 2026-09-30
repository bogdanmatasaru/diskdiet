/Records for UID/ { mine = ($4 == uid); if (mine) seen = 1 }
mine && /^ +Type:/ { t = $0; sub(/^ +Type: /, "", t); sub(/ \(0x[0-9a-f]+\)$/, "", t) }
mine && /^ +Disposition:/ && /\[enabled/ && (t == "login item" || t == "app" || t == "agent" || t == "legacy agent") { c++ }
END { if (seen) print c + 0 }
