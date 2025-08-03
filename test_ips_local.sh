#!/bin/bash

# Read JSON file
json_file="ips.json"
output_file="ips-local.json"

# Start JSON array
echo "[" > "$output_file"
first=true

# Read each entry
jq -c '.[]' "$json_file" | while read -r entry; do
    server=$(echo "$entry" | jq -r '.server')
    ip=$(echo "$entry" | jq -r '.ip')
    
    # Add comma for all except first entry
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "$output_file"
    fi
    
    # Ping with 5 packets, 1 second timeout per packet
    ping_output=$(ping -c 5 -W 1000 "$ip" 2>&1)
    
    if echo "$ping_output" | grep -q "100.0% packet loss\|cannot resolve\|No route"; then
        # Timeout or unreachable
        echo -n "{\"server\":\"$server\",\"ip\":\"$ip\",\"stability\":null,\"latency\":null}" >> "$output_file"
    else
        # Extract packet loss percentage
        loss=$(echo "$ping_output" | grep "packet loss" | sed 's/.*received, \([0-9.]*\)% packet loss.*/\1/')
        stability=$(echo "100 - $loss" | bc)
        
        # Extract average latency
        avg_line=$(echo "$ping_output" | grep "min/avg/max")
        if [ -n "$avg_line" ]; then
            latency=$(echo "$avg_line" | sed 's/.*min\/avg\/max\/[a-z]* = [0-9.]*\/\([0-9.]*\)\/.*/\1/')
        else
            # If no stats line, calculate from individual pings
            latency=$(echo "$ping_output" | grep "time=" | sed 's/.*time=\([0-9.]*\) ms/\1/' | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "null"}')
        fi
        
        echo -n "{\"server\":\"$server\",\"ip\":\"$ip\",\"stability\":$stability,\"latency\":$latency}" >> "$output_file"
    fi
    
    # Progress indicator
    echo -n "." >&2
done

# Close JSON array
echo "" >> "$output_file"
echo "]" >> "$output_file"

echo "" >&2
echo "Done! Results saved to $output_file" >&2