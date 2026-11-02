#!/usr/bin/env bash
# One-time provisioning. Run from inside the cloned repo on the EC2 instance:
#   cd ~/tasksphere && bash deploy/setup_ec2.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

APP_DIR="/home/ubuntu/tasksphere"
cd "$APP_DIR"

echo "==> Installing system packages"
sudo apt-get update -y
sudo apt-get install -y python3-venv python3-pip nginx git curl

echo "==> Creating virtualenv and installing dependencies"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo "==> Creating log directory"
sudo mkdir -p /var/log/tasksphere
sudo chown ubuntu:ubuntu /var/log/tasksphere

echo "==> Installing systemd service"
sudo cp deploy/tasksphere.service /etc/systemd/system/tasksphere.service
sudo systemctl daemon-reload
sudo systemctl enable --now tasksphere

echo "==> Configuring Nginx"
sudo cp deploy/nginx.conf /etc/nginx/sites-available/tasksphere
sudo ln -sf /etc/nginx/sites-available/tasksphere /etc/nginx/sites-enabled/tasksphere
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "==> Health check"
sleep 3
curl -fsS http://127.0.0.1/healthz && echo && echo "TaskSphere is live."