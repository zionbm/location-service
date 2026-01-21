#!/bin/bash

URL="http://localhost:3000/v1/locations"
INTERVAL=3

# Initial positions (Jerusalem-ish)
USER1_LAT=31.771959
USER1_LON=35.217018

USER2_LAT=31.772300
USER2_LON=35.217400

STEP=0.00005   # movement step (~5–6 meters)

echo "Starting simulation (Ctrl+C to stop)"
echo "----------------------------------"

while true; do
  # Simulate movement
  USER1_LAT=$(echo "$USER1_LAT + $STEP" | bc -l)
  USER1_LON=$(echo "$USER1_LON + $STEP" | bc -l)

  USER2_LAT=$(echo "$USER2_LAT - $STEP" | bc -l)
  USER2_LON=$(echo "$USER2_LON - $STEP" | bc -l)

  echo
  echo ">>> Sending user-1 location:"
  echo "{ \"id\": \"user-1\", \"lat\": $USER1_LAT, \"lon\": $USER1_LON }"

  RESPONSE1=$(curl -s -X POST "$URL" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"user-1\",\"lat\":$USER1_LAT,\"lon\":$USER1_LON}")

  echo "<<< Response user-1:"
  echo "$RESPONSE1"

  echo
  echo ">>> Sending user-2 location:"
  echo "{ \"id\": \"user-2\", \"lat\": $USER2_LAT, \"lon\": $USER2_LON }"

  RESPONSE2=$(curl -s -X POST "$URL" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"user-2\",\"lat\":$USER2_LAT,\"lon\":$USER2_LON}")

  echo "<<< Response user-2:"
  echo "$RESPONSE2"

  echo "----------------------------------"
  sleep $INTERVAL
done
