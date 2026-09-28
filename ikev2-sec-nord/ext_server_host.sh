#!/bin/bash

# Each .ovpn has several "remote" lines (one per port, same IP), and each server
# has two files (.udp.ovpn and .udp_2.6.ovpn) — take the first IP per file and
# emit each hostname once.
awk '
    { sub(/\r$/, "") }
    FNR == 1 { n++; files[n] = FILENAME }
    /^remote / && !(FILENAME in ip) { ip[FILENAME] = $2 }
    /^verify-x509-name CN=/ && !(FILENAME in host) { h = $0; sub(/^verify-x509-name CN=/, "", h); host[FILENAME] = h }
    END {
        print "["
        first = 1
        for (i = 1; i <= n; i++) {
            f = files[i]
            if (ip[f] == "" || host[f] == "" || seen[host[f]]++) continue
            if (!first) print ","
            first = 0
            printf "  {\"hostname\":\"%s\",\"ip\":\"%s\"}\n", host[f], ip[f]
        }
        print "]"
    }
' ovpn_udp/*.ovpn > servers.json

echo "Done. Output: servers.json"
