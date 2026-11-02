#!/usr/bin/env bash
# Installs and starts the CloudWatch agent on the EC2 instance.
# Requires an IAM role with CloudWatchAgentServerPolicy attached to the instance.
set -euo pipefail

ARCH=$(dpkg --print-architecture)   # amd64 or arm64
URL="https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/${ARCH}/latest/amazon-cloudwatch-agent.deb"

echo "==> Downloading CloudWatch agent (${ARCH})"
wget -q -O /tmp/cw-agent.deb "$URL"
sudo dpkg -i -E /tmp/cw-agent.deb

echo "==> Installing config"
sudo cp "$(dirname "$0")/amazon-cloudwatch-agent.json" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "==> Starting agent"
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status