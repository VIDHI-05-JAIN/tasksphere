#!/usr/bin/env bash
# Usage: bash create_dashboard_and_alarm.sh <instance-id> <region> [alert-email]
set -euo pipefail

INSTANCE_ID="${1:?Usage: $0 <instance-id> <region> [alert-email]}"
REGION="${2:?Usage: $0 <instance-id> <region> [alert-email]}"
EMAIL="${3:-}"

ALARM_ACTIONS=()
if [ -n "$EMAIL" ]; then
  echo "==> Creating SNS topic and subscribing $EMAIL"
  TOPIC_ARN=$(aws sns create-topic --name tasksphere-alerts --region "$REGION" --query TopicArn --output text)
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
    --notification-endpoint "$EMAIL" --region "$REGION" >/dev/null
  ALARM_ACTIONS=(--alarm-actions "$TOPIC_ARN")
  echo "    Check your inbox and CONFIRM the subscription."
fi

echo "==> Creating dashboard"
BODY=$(cat <<EOF
{
  "widgets": [
    {"type":"metric","x":0,"y":0,"width":12,"height":6,
     "properties":{"title":"CPU Utilization (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":300,
       "metrics":[["AWS/EC2","CPUUtilization","InstanceId","$INSTANCE_ID"]]}},
    {"type":"metric","x":12,"y":0,"width":12,"height":6,
     "properties":{"title":"Memory Used (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":300,
       "metrics":[["CWAgent","mem_used_percent","InstanceId","$INSTANCE_ID"]]}},
    {"type":"metric","x":0,"y":6,"width":12,"height":6,
     "properties":{"title":"Disk Used (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":300,
       "metrics":[["CWAgent","disk_used_percent","InstanceId","$INSTANCE_ID"]]}},
    {"type":"log","x":12,"y":6,"width":12,"height":6,
     "properties":{"title":"Nginx access log (latest 20)","region":"$REGION","view":"table",
       "query":"SOURCE 'tasksphere-nginx-access' | fields @timestamp, @message | sort @timestamp desc | limit 20"}}
  ]
}
EOF
)
aws cloudwatch put-dashboard --dashboard-name TaskSphere --dashboard-body "$BODY" --region "$REGION"

echo "==> Creating CPU alarm (>60% avg over 5 min)"
aws cloudwatch put-metric-alarm \
  --alarm-name TaskSphere-High-CPU \
  --alarm-description "TaskSphere EC2 CPU above 60%" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 --evaluation-periods 1 \
  --threshold 60 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  ${ALARM_ACTIONS[@]+"${ALARM_ACTIONS[@]}"} \
  --region "$REGION"

echo "Done. Dashboard: TaskSphere | Alarm: TaskSphere-High-CPU"