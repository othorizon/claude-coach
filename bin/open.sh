#!/usr/bin/env bash
# claude-coach open.sh
# 幂等地开启动画窗口。被 SessionStart(sweep)/UserPromptSubmit/PreToolUse hook 触发。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

MODE_ARG="${1:-run}"

# 进门先打日志，方便排查（之前在 TTY 检查那里静默退出过）
cw_log "open.sh invoked mode_arg=$MODE_ARG TMUX=${TMUX:-} TERM_PROGRAM=${TERM_PROGRAM:-} PPID=$PPID"

# 非交互显式声明（claude -p 模式 / CI 场景）才静默退出
# 不再依赖 [[ -t 1 ]] —— hook 的 stdout 不是 TTY，那个检查会让脚本永远不跑
if [[ -n "${CLAUDE_NON_INTERACTIVE:-}" || -n "${CI:-}" ]]; then
  cw_log "skip: non-interactive env detected"
  exit 0
fi

# stdin 里的 hook payload，只有 session_id 是必需的
HOOK_INPUT=""
if [[ ! -t 0 ]]; then
  HOOK_INPUT=$(cat 2>/dev/null || true)
fi
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [[ -z "$SESSION_ID" && -n "$HOOK_INPUT" ]] && command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
fi
[[ -z "$SESSION_ID" ]] && SESSION_ID="default"

DATA_DIR=$(cw_data_dir)
RUNTIME_FILE=$(cw_runtime_file "$SESSION_ID")
CLAUDE_PID="${PPID:-$$}"  # hook 的 PPID 通常就是 claude 进程

# ───────── sweep 模式：只清理孤儿 ─────────
if [[ "$MODE_ARG" == "sweep" ]]; then
  cw_log "sweep start"
  shopt -s nullglob
  for rt in "$DATA_DIR"/runtime-*.json; do
    if ! command -v jq >/dev/null 2>&1; then
      rm -f "$rt"
      continue
    fi
    claude_pid=$(jq -r '.claude_pid // empty' "$rt" 2>/dev/null)
    anim_pid=$(jq -r '.pid // empty' "$rt" 2>/dev/null)
    anim_start=$(jq -r '.start_time // empty' "$rt" 2>/dev/null)
    pane_id=$(jq -r '.pane_id // empty' "$rt" 2>/dev/null)
    mode=$(jq -r '.mode // empty' "$rt" 2>/dev/null)

    # claude_pid 还活着 → 不是孤儿，留着
    if [[ -n "$claude_pid" ]] && kill -0 "$claude_pid" 2>/dev/null; then
      cw_log "sweep keep $(basename "$rt")"
      continue
    fi

    cw_log "sweep clean $(basename "$rt")"
    # 清理对应的窗口/pane
    if [[ "$mode" == "tmux" && -n "$pane_id" ]]; then
      tmux kill-pane -t "$pane_id" 2>/dev/null || true
    elif [[ -n "$anim_pid" ]] && cw_is_alive "$anim_pid" "$anim_start"; then
      kill -TERM "$anim_pid" 2>/dev/null || true
    fi
    rm -f "$rt"
  done
  exit 0
fi

# ───────── 幂等检查：已开就直接退出 ─────────
if [[ -f "$RUNTIME_FILE" ]] && command -v jq >/dev/null 2>&1; then
  pid=$(jq -r '.pid // empty' "$RUNTIME_FILE" 2>/dev/null)
  start_time=$(jq -r '.start_time // empty' "$RUNTIME_FILE" 2>/dev/null)
  mode=$(jq -r '.mode // empty' "$RUNTIME_FILE" 2>/dev/null)
  pane_id=$(jq -r '.pane_id // empty' "$RUNTIME_FILE" 2>/dev/null)

  if [[ "$mode" == "tmux" && -n "$pane_id" ]]; then
    if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane_id"; then
      cw_log "open idempotent (tmux pane $pane_id alive)"
      exit 0
    fi
  elif cw_is_alive "$pid" "$start_time"; then
    cw_log "open idempotent (pid $pid alive)"
    exit 0
  fi
  # stale → 继续往下走重开
  rm -f "$RUNTIME_FILE"
fi

# ───────── 决定模式 ─────────
MODE=$(cw_detect_mode)
ANIMATION="$SCRIPT_DIR/animation.sh"
chmod +x "$ANIMATION" 2>/dev/null || true

cw_log "open mode=$MODE session=$SESSION_ID"

# ───────── tmux 模式 ─────────
open_tmux() {
  [[ -z "${TMUX:-}" ]] && return 1
  local size dir
  size=$(cw_get_config tmux_size_percent 70)
  dir=$(cw_get_config tmux_split_direction h)
  case "$dir" in h|v) ;; *) dir=h;; esac
  case "$size" in ''|*[!0-9]*) size=70;; esac
  (( size < 20 )) && size=20
  (( size > 90 )) && size=90

  local target="${TMUX_PANE:-}"
  local pane_id
  pane_id=$(tmux split-window -P -F '#{pane_id}' \
    ${target:+-t "$target"} \
    "-${dir}" "-p" "$size" \
    "exec '$ANIMATION' '$SESSION_ID' '$RUNTIME_FILE' '$CLAUDE_PID'" 2>/dev/null) || return 1

  # 写 runtime 文件 — 等 animation.sh 写入自己 pid 也可以，但 tmux 模式 pane_id 已经够
  local now; now=$(date +%s)
  local payload
  payload=$(jq -n \
    --arg mode tmux \
    --arg pane "$pane_id" \
    --arg session "$SESSION_ID" \
    --arg cp "$CLAUDE_PID" \
    --argjson start "$now" \
    '{mode:$mode, pane_id:$pane, session_id:$session, claude_pid:($cp|tonumber), started_at:$start, session_ms:0}')
  cw_atomic_write "$RUNTIME_FILE" "$payload"
  return 0
}

# ───────── popup 模式 ─────────
open_popup() {
  local pid_file="$DATA_DIR/popup-pid-${SESSION_ID}"
  rm -f "$pid_file"

  local custom; custom=$(cw_get_config popup_command "")
  local script_invoke="'$ANIMATION' '$SESSION_ID' '$RUNTIME_FILE' '$CLAUDE_PID' '$pid_file'"

  if [[ -n "$custom" ]]; then
    # 用户自定义命令，{script} 占位
    local cmd="${custom//\{script\}/$script_invoke}"
    nohup bash -c "$cmd" >/dev/null 2>&1 &
  else
    case "$(uname -s)" in
      Darwin)
        local term_program="${TERM_PROGRAM:-Terminal}"
        if [[ "$term_program" == "iTerm.app" ]]; then
          osascript >/dev/null 2>&1 <<EOF
tell application "iTerm2"
  create window with default profile command "/bin/bash -c \"$script_invoke\""
end tell
EOF
        else
          osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
  activate
  do script "exec /bin/bash -c \"$script_invoke\""
end tell
EOF
        fi
        ;;
      Linux)
        # 尝试常见终端模拟器
        for term in alacritty kitty wezterm gnome-terminal konsole xterm; do
          if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
              alacritty|kitty|wezterm) nohup "$term" -e bash -c "$script_invoke" >/dev/null 2>&1 & ;;
              gnome-terminal) nohup "$term" -- bash -c "$script_invoke" >/dev/null 2>&1 & ;;
              konsole) nohup "$term" -e bash -c "$script_invoke" >/dev/null 2>&1 & ;;
              xterm) nohup "$term" -e bash -c "$script_invoke" >/dev/null 2>&1 & ;;
            esac
            break
          fi
        done
        ;;
      *)
        cw_log "popup unsupported os $(uname -s)"
        return 1
        ;;
    esac
  fi

  # 等 animation.sh 写自己的 PID
  local pid=""
  for _ in $(seq 1 40); do
    if [[ -f "$pid_file" ]]; then
      pid=$(cat "$pid_file" 2>/dev/null)
      [[ -n "$pid" ]] && break
    fi
    sleep 0.05
  done
  [[ -z "$pid" ]] && { cw_log "popup pid never written"; return 1; }

  local start_time; start_time=$(cw_pid_start_time "$pid")
  local now; now=$(date +%s)
  local payload
  payload=$(jq -n \
    --arg mode popup \
    --argjson pid "$pid" \
    --arg start "$start_time" \
    --arg session "$SESSION_ID" \
    --arg cp "$CLAUDE_PID" \
    --argjson started "$now" \
    '{mode:$mode, pid:$pid, start_time:$start, session_id:$session, claude_pid:($cp|tonumber), started_at:$started, session_ms:0}')
  cw_atomic_write "$RUNTIME_FILE" "$payload"
  rm -f "$pid_file"
  return 0
}

case "$MODE" in
  tmux)
    open_tmux || cw_log "open_tmux failed"
    ;;
  popup)
    open_popup || cw_log "open_popup failed"
    ;;
  *)
    cw_log "unknown mode $MODE"
    ;;
esac

exit 0
