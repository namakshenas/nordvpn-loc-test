# NordVPN IKEv2/SEC Compatible hostname:ip

The servers list can be obtained from here: `https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip`. I extracted them via the following script and saved them in `servers.json`.

```bash
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
```

All servers receiving pings are stored in `active_servers.json`.

Note that `root.der` is also required to set `ikev2` on any device.
