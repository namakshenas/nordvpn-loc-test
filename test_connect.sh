#!/bin/bash

# Read JSON and process each entry
jq -c '.[]' ips.json | while read entry; do
    server=$(echo "$entry" | jq -r '.server')
    ip=$(echo "$entry" | jq -r '.ip')
    
    # Ping once with 2 second timeout
    if result=$(ping -c 1 -W 2 "$ip" 2>/dev/null); then
        # Extract latency from summary line (min/avg/max/stddev)
        lat=$(echo "$result" | grep 'round-trip' | awk -F'=' '{print $2}' | awk -F'/' '{print $1}' | tr -d ' ')
        
        # If lat is empty, set to null
        if [ -z "$lat" ]; then
            lat="null"
        fi
    else
        lat="null"
    fi
    
    # Output valid JSON
    jq -n --arg s "$server" --arg i "$ip" --argjson l "$lat" \
       '{server: $s, ip: $i, lat: $l}'
done | jq -s '.' > ips-IR-cell.json