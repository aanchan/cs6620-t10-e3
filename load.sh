#!/bin/bash
# Observability Lab - load generator. Run in AWS CloudShell.
# Usage: ./load.sh <function-name> [minutes]   (default: 20 minutes)

FN="$1"
MINUTES="${2:-20}"
if [ -z "$FN" ]; then
  echo "Usage: ./load.sh <function-name> [minutes]"
  exit 1
fi

ROUTES=(user order inventory payment search)
START=$(date +%s)
END=$(( START + MINUTES * 60 ))
SENT=0

echo "Sending traffic to $FN for $MINUTES minutes. Press Ctrl+C to stop early."
while [ "$(date +%s)" -lt "$END" ]; do
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ROUTE=${ROUTES[$RANDOM % 5]}
    ITEM=$(( RANDOM % 1000 + 1 ))
    ELAPSED=$(( $(date +%s) - START ))
    aws lambda invoke \
      --function-name "$FN" \
      --cli-binary-format raw-in-base64-out \
      --payload "{\"route\":\"$ROUTE\",\"item_id\":$ITEM,\"elapsed\":$ELAPSED}" \
      /dev/null > /dev/null 2>&1 &
  done
  wait
  SENT=$(( SENT + 10 ))
  echo "Sent $SENT requests"
done
echo "Done."
