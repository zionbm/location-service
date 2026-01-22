#!/bin/bash

URL="http://localhost:3000/v1/locations"
INTERVAL=3
CLIENT_COUNT=10

BASE_LAT=31.771959
BASE_LON=35.217018

STEP=0.00005

declare -a IDS LATS LONS DIR_LAT DIR_LON

# Init clients
for i in $(seq 1 $CLIENT_COUNT); do
  IDS[$i]="user-$i"
  LATS[$i]=$(echo "$BASE_LAT + ($i * 0.00002)" | bc -l)
  LONS[$i]=$(echo "$BASE_LON + ($i * 0.00002)" | bc -l)
  DIR_LAT[$i]=$((RANDOM % 2 == 0 ? 1 : -1))
  DIR_LON[$i]=$((RANDOM % 2 == 0 ? 1 : -1))
done

echo
echo "{"
echo "  \"simulation\": \"started\","
echo "  \"clients\": $CLIENT_COUNT"
echo "}"
echo

while true; do
  for i in $(seq 1 $CLIENT_COUNT); do
    LATS[$i]=$(echo "${LATS[$i]} + (${DIR_LAT[$i]} * $STEP)" | bc -l)
    LONS[$i]=$(echo "${LONS[$i]} + (${DIR_LON[$i]} * $STEP)" | bc -l)

    REQUEST=$(jq -n \
      --arg id "${IDS[$i]}" \
      --argjson lat "${LATS[$i]}" \
      --argjson lon "${LONS[$i]}" \
      '{id:$id, lat:$lat, lon:$lon}')

    RESPONSE=$(curl -s -X POST "$URL" \
      -H "Content-Type: application/json" \
      -d "$REQUEST")

    echo
    echo "{"
    echo "  \"client\": \"${IDS[$i]}\","
    echo "  \"request\":"
    echo "$REQUEST" | jq
    echo "  ,\"response\":"
    echo "$RESPONSE" | jq
    echo "}"
  done

  sleep $INTERVAL
done
