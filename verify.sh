#!/bin/bash
# Instructor check for Assignment 3. Run in Learner Lab CloudShell (us-east-1).
# Needs lambda_function.py and load.sh in the same folder.
#
#   ./verify.sh <test-nuid> [email]   run the whole assignment (~10 min)
#   ./verify.sh --cleanup          delete everything it made

set -u
FN=obs-lab-verify
ALARM=obs-alarm-verify
TOPIC=obs-topic-verify
LOG_GROUP=/aws/lambda/$FN

if [ "${1:-}" = "--cleanup" ]; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  REGION=$(aws configure get region || echo us-east-1)
  aws cloudwatch delete-alarms --alarm-names "$ALARM"
  aws sns delete-topic --topic-arn "arn:aws:sns:$REGION:$ACCOUNT:$TOPIC"
  aws lambda delete-function --function-name "$FN"
  aws logs delete-log-group --log-group-name "$LOG_GROUP"
  echo "Cleaned up."
  exit 0
fi

SEED="${1:?Usage: ./verify.sh <test-nuid> [email]}"
EMAIL="${2:-}"

echo "== Expected results for NUID $SEED =="
SEED=$SEED python3 - << 'PY'
import lambda_function as f
c = f.CONFIG
cause = c["cause"]
v = cause["value"]
if cause["type"] == "threshold":
    desc = "item_id > %d" % v
else:
    desc = "item_id divisible by %d" % v
rate = 100 * sum(f.cause_triggers(cause, i) for i in range(1, 1001)) / 1000
print("  failing route: %s  (~%.0f%% errors)" % (c["failing_route"], rate))
print("  hidden cause:  %s" % desc)
print("  slow route:    %s  (P95 ~%d ms)" % (c["slow_route"], c["slow_ms"] + 180))
print("  problems start: %g min after traffic starts" % (c["onset_s"] / 60))
PY
FAILING=$(SEED=$SEED python3 -c "import lambda_function as f; print(f.CONFIG['failing_route'])")
ONSET=$(SEED=$SEED python3 -c "import lambda_function as f; print(f.CONFIG['onset_s'])")

echo "== 1. Deploy function =="
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ROLE="arn:aws:iam::$ACCOUNT:role/LabRole"
rm -f fn.zip && zip -q fn.zip lambda_function.py
aws lambda create-function --function-name "$FN" --runtime python3.12 \
  --role "$ROLE" --handler lambda_function.lambda_handler \
  --zip-file fileb://fn.zip --timeout 10 \
  --environment "Variables={SEED=$SEED}" > /dev/null || exit 1
aws lambda wait function-active-v2 --function-name "$FN"
echo "  ok"

echo "== 2. SNS topic + alarm =="
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC" --query TopicArn --output text)
if [ -n "$EMAIL" ]; then
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL" > /dev/null
  echo "  Check $EMAIL and CONFIRM the subscription now."
fi
aws cloudwatch put-metric-alarm --alarm-name "$ALARM" \
  --namespace AWS/Lambda --metric-name Errors \
  --dimensions "Name=FunctionName,Value=$FN" \
  --statistic Sum --period 60 --evaluation-periods 1 --threshold 4 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching --alarm-actions "$TOPIC_ARN"
echo "  ok"

echo "== 3. Send traffic (8 min) =="
START=$(date +%s)
./load.sh "$FN" 8 | tail -n 1

echo "== 4. Wait 60s for logs and metrics =="
sleep 60
END=$(date +%s)

run_query () {
  echo "-- $1"
  QID=$(aws logs start-query --log-group-name "$LOG_GROUP" \
    --start-time "$(( START + ONSET ))" --end-time "$END" \
    --query-string "$2" --query queryId --output text)
  for i in $(seq 1 30); do
    STATUS=$(aws logs get-query-results --query-id "$QID" --query status --output text)
    [ "$STATUS" = "Complete" ] && break
    sleep 2
  done
  aws logs get-query-results --query-id "$QID" --query 'results[*][*].value' --output text
}

echo "== 5. Logs Insights (from when problems started) =="
run_query "Requests by route and status" \
  'filter ispresent(route) | stats count(*) as n by route, status | sort route'
run_query "P95 latency by route" \
  'filter ispresent(latency_ms) | stats pct(latency_ms, 95) as p95 by route | sort p95 desc'
run_query "Fault errors on $FAILING (min/max item_id)" \
  "filter route = \"$FAILING\" and error like /lookup failed/ | stats min(item_id), max(item_id), count(*)"
run_query "Sample failing item_ids on $FAILING" \
  "filter route = \"$FAILING\" and error like /lookup failed/ | fields item_id | sort item_id asc | limit 15"

echo "== 6. Alarm history =="
aws cloudwatch describe-alarm-history --alarm-name "$ALARM" \
  --history-item-type StateUpdate --query 'AlarmHistoryItems[*].[Timestamp,HistorySummary]' --output text

echo
echo "Compare section 5 with the expected results at the top."
echo "When done: ./verify.sh --cleanup"
