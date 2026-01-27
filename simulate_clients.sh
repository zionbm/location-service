#!/bin/bash

URL="http://localhost:3000/v1/locations"
AUTH_URL="http://localhost:4000/v1/auth"
INTERVAL=3
CLIENT_COUNT=5

# iOS simulator default (Tel Aviv)
BASE_LAT=32.0853
BASE_LON=34.7818

STEP=0.00005

declare -a IDS LATS LONS DIR_LAT DIR_LON TOKENS

# Init clients
for i in $(seq 1 $CLIENT_COUNT); do
  IDS[$i]="user-$i"
  LATS[$i]=$(echo "$BASE_LAT + ($i * 0.00002)" | bc -l)
  LONS[$i]=$(echo "$BASE_LON + ($i * 0.00002)" | bc -l)
  DIR_LAT[$i]=$((RANDOM % 2 == 0 ? 1 : -1))
  DIR_LON[$i]=$((RANDOM % 2 == 0 ? 1 : -1))
done

# Register + login to get tokens
for i in $(seq 1 $CLIENT_COUNT); do
  EMAIL="${IDS[$i]}@example.com"
  PASSWORD="Pass1234!"
  DOG_NAME="Dog-${i}"

  REGISTER_PAYLOAD=$(jq -n \
    --arg email "$EMAIL" \
    --arg password "$PASSWORD" \
    --arg dogName "$DOG_NAME" \
    '{email:$email, password:$password, dogName:$dogName}')

  # Register (ignore if already exists)
  curl -s -X POST "$AUTH_URL/register" \
    -H "Content-Type: application/json" \
    -d "$REGISTER_PAYLOAD" >/dev/null

  LOGIN_PAYLOAD=$(jq -n \
    --arg email "$EMAIL" \
    --arg password "$PASSWORD" \
    '{email:$email, password:$password}')

  LOGIN_RESPONSE=$(curl -s -X POST "$AUTH_URL/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD")

  TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
  PUBLIC_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.publicId // empty')
  if [[ -z "$TOKEN" || -z "$PUBLIC_ID" ]]; then
    echo "Failed to login for ${EMAIL}: $LOGIN_RESPONSE"
    exit 1
  fi
  TOKENS[$i]="$TOKEN"
  IDS[$i]="$PUBLIC_ID"
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

    AUTH_HEADER="Authorization: Bearer ${TOKENS[$i]}"
    RESPONSE=$(curl -s -X POST "$URL" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      -d "$REQUEST")

    echo
    echo "{"
    echo "  \"client\": \"${IDS[$i]}\","
    echo "  \"request\": {"
    echo "    \"headers\": {"
    echo "      \"Content-Type\": \"application/json\","
    echo "      \"Authorization\": \"Bearer ${TOKENS[$i]}\""
    echo "    },"
    echo "    \"body\":"
    echo "$REQUEST" | jq
    echo "  },"
    echo "  \"response\":"
    echo "$RESPONSE" | jq
    echo "}"
  done

  sleep $INTERVAL
done
