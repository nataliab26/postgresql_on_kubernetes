#!/bin/sh
export PGCONNECT_TIMEOUT=2

while true; do
  POD=$(psql -X -tA -c "SELECT coalesce(nullif(replace(substr(current_setting('primary_slot_name'), 7), '_', '-'), ''), host(inet_server_addr()))" 2>/dev/null) \
    || POD="BRAK POŁĄCZENIA"
  echo "$(date +%T)  $POD"
  sleep 1
done
