#!/usr/bin/env bash
set -euo pipefail

# Everything is inside a function so bash reads the whole script before
# running it. This makes it safe for git to replace this file mid-run.
main() {
  cd /home/ubuntu/tasksphere

  echo "==> Pulling latest code"
  git fetch origin main
  git reset --hard origin/main

  echo "==> Installing dependencies"
  ./venv/bin/pip install -q -r requirements.txt

  echo "==> Restarting service"
  sudo systemctl restart tasksphere

  echo "==> Health check"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS http://127.0.0.1/healthz >/dev/null; then
      echo "Healthy. Deploy complete."
      return 0
    fi
    sleep 2
  done

  echo "Health check FAILED. Recent logs:"
  sudo journalctl -u tasksphere -n 30 --no-pager
  return 1
}

main "$@"
exit 0