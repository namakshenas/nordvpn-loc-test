#!/bin/bash

tmp="/tmp/ping_results_$$"
> "$tmp"

echo "Pinging servers..."
count=0

# Ping all IPs in parallel
while IFS= read -r line; do
    if [[ $line =~ \"hostname\":\"([^\"]+)\",\"ip\":\"([^\"]+)\" ]]; then
        hostname="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[2]}"
        ((count++))
        
        # Increase timeout to 2 seconds and use 2 packets
        (ping -c 2 -W 2 "$ip" &>/dev/null && echo "{\"hostname\":\"$hostname\",\"ip\":\"$ip\"}" >> "$tmp") &
        
        # Limit parallel jobs to 50 at a time
        if (( count % 50 == 0 )); then
            wait
        fi
    fi
done < servers.json

# Wait for remaining pings
wait

echo "Found $(wc -l < "$tmp" | tr -d ' ') active servers"

# Build JSON from results
echo "[" > active_servers.json
first=true
while IFS= read -r line; do
    [ "$first" = true ] && first=false || echo "," >> active_servers.json
    echo "  $line" >> active_servers.json
done < "$tmp"
echo "]" >> active_servers.json

rm "$tmp"
echo "Done. Output: active_servers.json"