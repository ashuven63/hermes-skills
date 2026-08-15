#!/bin/bash
# Start the research-digest static server (idempotent).
# Usage: ./start.sh [port]   (default 8088, or $RESEARCH_PORT)
set -e
cd "$(dirname "$0")"
PORT="${1:-${RESEARCH_PORT:-8088}}"
HOST="${RESEARCH_HOST:-127.0.0.1}"

# No-op if something is already listening on the port.
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "research-serve already listening on $PORT — leaving it running."
    exit 0
  fi
fi

mkdir -p "$HOME/research"
nohup python3 "$PWD/serve.py" "$PORT" > "$PWD/serve.log" 2>&1 &
echo "research-serve started (PID $!) on http://$HOST:$PORT"
echo "Logs: $PWD/serve.log"
