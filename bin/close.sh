#!/usr/bin/env bash
# claude-coach close.sh
# 同步关闭动画窗口。被 Notification/Stop/SessionEnd hook 触发。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

FINAL=""
[[ "${1:-}" == "final" ]] && FINAL=1

cw_log "close.sh invoked final=${FINAL:-0}"

HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(cat 2>/dev/null || true)
fi
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [[ -z "$SESSION_ID" && -n "$HOOK_INPUT" ]] && command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
fi
[[ -z "$SESSION_ID" ]] && SESSION_ID="default"

RUNTIME_FILE=$(cw_runtime_file "$SESSION_ID")
[[ -f "$RUNTIME_FILE" ]] || exit 0
command -v jq >/dev/null 2>&1 || { rm -f "$RUNTIME_FILE"; exit 0; }

MODE=$(jq -r '.mode // empty' "$RUNTIME_FILE" 2>/dev/null)
PID=$(jq -r '.pid // empty' "$RUNTIME_FILE" 2>/dev/null)
START_TIME=$(jq -r '.start_time // empty' "$RUNTIME_FILE" 2>/dev/null)
PANE_ID=$(jq -r '.pane_id // empty' "$RUNTIME_FILE" 2>/dev/null)

cw_log "close mode=$MODE pid=$PID pane=$PANE_ID final=$FINAL"

case "$MODE" in
  tmux)
    if [[ -n "$PANE_ID" ]]; then
      tmux kill-pane -t "$PANE_ID" 2>/dev/null || true
    fi
    ;;
  popup)
    if [[ -n "$PID" ]] && cw_is_alive "$PID" "$START_TIME"; then
      kill -TERM "$PID" 2>/dev/null || true
      # 同步等最多 500ms
      for _ in $(seq 1 10); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.05
      done
      # 还活着就强杀
      if kill -0 "$PID" 2>/dev/null; then
        kill -KILL "$PID" 2>/dev/null || true
      fi
    fi
    ;;
esac

rm -f "$RUNTIME_FILE"
exit 0
