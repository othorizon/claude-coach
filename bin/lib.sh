#!/usr/bin/env bash
# claude-coach 公共库
# source 进 open.sh / close.sh / animation.sh / render-stats.sh 使用

set -u

CW_PLUGIN_NAME="claude-coach"

cw_data_dir() {
  local dir
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    dir="$CLAUDE_PLUGIN_DATA"
  else
    dir="$HOME/.claude/plugins/data/$CW_PLUGIN_NAME"
  fi
  mkdir -p "$dir" 2>/dev/null
  echo "$dir"
}

cw_runtime_file() {
  local sid="${1:-${CLAUDE_SESSION_ID:-default}}"
  echo "$(cw_data_dir)/runtime-${sid}.json"
}

cw_stats_file() {
  echo "$(cw_data_dir)/stats.json"
}

cw_lock_dir() {
  echo "$(cw_data_dir)/stats.lock"
}

cw_log() {
  # 始终写日志（量很小，便于排查）；用户可定期清空 debug.log
  printf '[cw %s pid=%d] %s\n' "$(date +%H:%M:%S)" "$$" "$*" >> "$(cw_data_dir)/debug.log" 2>/dev/null
}

cw_acquire_lock() {
  local lock; lock=$(cw_lock_dir)
  local tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if (( tries > 100 )); then
      rmdir "$lock" 2>/dev/null
      return 1
    fi
    sleep 0.05
  done
}

cw_release_lock() {
  rmdir "$(cw_lock_dir)" 2>/dev/null || true
}

cw_atomic_write() {
  local path="$1" content="$2"
  local tmp="${path}.tmp.$$"
  printf '%s' "$content" > "$tmp" && mv -f "$tmp" "$path"
}

cw_pid_start_time() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '
}

cw_is_alive() {
  local pid="$1" expected_start="${2:-}"
  [[ -n "$pid" && "$pid" != "null" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if [[ -n "$expected_start" ]]; then
    local actual; actual=$(cw_pid_start_time "$pid")
    [[ "$actual" == "$expected_start" ]] || return 1
  fi
  return 0
}

# 读 ~/.claude/settings.json 的 pluginConfigs，找匹配 claude-coach 的 options.<key>
# 用法: cw_user_config display_mode
cw_user_config() {
  local key="$1"
  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg key "$key" '
    .pluginConfigs // {} | to_entries[]
    | select(.key | startswith("claude-coach"))
    | .value.options[$key] // empty
  ' "$settings" 2>/dev/null | head -n1
}

# 读 user_config，env var 优先（CLAUDE_COACH_MODE 等），settings 次之，最后是默认值
cw_get_config() {
  local key="$1" default="$2"
  local env_name="CLAUDE_COACH_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
  local v="${!env_name:-}"
  [[ -n "$v" ]] && { echo "$v"; return; }
  v=$(cw_user_config "$key")
  [[ -n "$v" && "$v" != "null" ]] && { echo "$v"; return; }
  echo "$default"
}

cw_detect_mode() {
  local m; m=$(cw_get_config display_mode auto)
  if [[ "$m" == "auto" ]]; then
    [[ -n "${TMUX:-}" ]] && echo tmux || echo popup
  else
    echo "$m"
  fi
}

# 累计 elapsed_seconds 进 stats.json
cw_update_stats() {
  local elapsed="$1"
  local stats; stats=$(cw_stats_file)
  command -v jq >/dev/null 2>&1 || return 0
  cw_acquire_lock || return 0
  local current="{}"
  [[ -f "$stats" ]] && current=$(cat "$stats" 2>/dev/null || echo "{}")
  local today; today=$(date +%Y-%m-%d)
  local new
  new=$(echo "$current" | jq --argjson e "$elapsed" --arg day "$today" '
    .total_ms = ((.total_ms // 0) + ($e * 1000))
    | .daily = (.daily // {})
    | .daily[$day] = ((.daily[$day] // 0) + ($e * 1000))
    | .last_updated = (now | floor)
  ') || { cw_release_lock; return 1; }
  cw_atomic_write "$stats" "$new"
  cw_release_lock
}

# 把会话当前累计写到 runtime 文件的 session_ms 字段，供 stats skill 读取
cw_update_session_ms() {
  local rt="$1" ms="$2"
  [[ -f "$rt" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local content; content=$(cat "$rt" 2>/dev/null) || return 0
  local new; new=$(echo "$content" | jq --argjson ms "$ms" '.session_ms = $ms') || return 0
  cw_atomic_write "$rt" "$new"
}
