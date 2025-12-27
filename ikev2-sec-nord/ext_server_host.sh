#!/bin/bash

echo "[" > servers.json
first=true

for file in ovpn_udp/*.ovpn; do
    ip=$(grep "^remote " "$file" | awk '{print $2}')
    hostname=$(grep "^verify-x509-name CN=" "$file" | cut -d= -f2)
    
    if [ -n "$ip" ] && [ -n "$hostname" ]; then
        [ "$first" = true ] && first=false || echo "," >> servers.json
        echo "  {\"hostname\":\"$hostname\",\"ip\":\"$ip\"}" >> servers.json
    fi
done

echo "]" >> servers.json
echo "Done. Output: servers.json"