#!/usr/bin/env bash
# claude-coach render-stats.sh
# 渲染累计运动统计面板。被 /claude-coach:stats skill 调用。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

STATS=$(cw_stats_file)

if ! command -v jq >/dev/null 2>&1; then
  cat <<EOF
⚠️  缺少 jq。请安装后重试：
    macOS:  brew install jq
    Linux:  apt-get install jq / yum install jq
EOF
  exit 0
fi

if [[ ! -f "$STATS" ]]; then
  cat <<'EOF'
🌿 claude-coach · 你的健康账本
──────────────────────────────────
还没有任何运动记录。

让 Claude 跑一些任务，动画窗口会在 Claude 干活时自动弹出，
跟着练 1-2 分钟，下次回来看就有数据啦 💪
EOF
  exit 0
fi

# 累计 / 今日
TOTAL_MS=$(jq -r '.total_ms // 0' "$STATS")
TODAY=$(date +%Y-%m-%d)
TODAY_MS=$(jq -r --arg d "$TODAY" '.daily[$d] // 0' "$STATS")

# 本会话（如果 runtime 文件还存在）
SESSION_MS=0
if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
  RT=$(cw_runtime_file "$CLAUDE_SESSION_ID")
  if [[ -f "$RT" ]]; then
    SESSION_MS=$(jq -r '.session_ms // 0' "$RT" 2>/dev/null || echo 0)
  fi
fi

format_duration() {
  local total_ms="${1:-0}"
  local total_s=$(( total_ms / 1000 ))
  local h=$(( total_s / 3600 ))
  local m=$(( (total_s % 3600) / 60 ))
  local s=$(( total_s % 60 ))
  if (( h > 0 )); then
    printf '%dh %02dm %02ds' "$h" "$m" "$s"
  elif (( m > 0 )); then
    printf '%dm %02ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

short_min() {
  local ms="$1"
  local m=$(( ms / 60000 ))
  echo "$m"
}

echo "🌿 claude-coach · 你的健康账本"
echo "──────────────────────────────────"
printf '累计运动  %s\n' "$(format_duration "$TOTAL_MS")"
printf '今日      %s\n' "$(format_duration "$TODAY_MS")"
printf '本会话    %s\n' "$(format_duration "$SESSION_MS")"
echo
echo "最近 7 天："

# 算最近 7 天峰值，用来归一化柱状图宽度
MAX_MIN=0
for i in 6 5 4 3 2 1 0; do
  day=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d 2>/dev/null)
  [[ -z "$day" ]] && continue
  ms=$(jq -r --arg d "$day" '.daily[$d] // 0' "$STATS")
  m=$(( ms / 60000 ))
  (( m > MAX_MIN )) && MAX_MIN=$m
done
(( MAX_MIN == 0 )) && MAX_MIN=1

BAR_WIDTH=20
for i in 6 5 4 3 2 1 0; do
  day=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d 2>/dev/null)
  [[ -z "$day" ]] && continue
  ms=$(jq -r --arg d "$day" '.daily[$d] // 0' "$STATS")
  m=$(( ms / 60000 ))
  # 加 30s 也按 1m 显示，避免短时间运动全是 0
  s=$(( (ms % 60000) / 1000 ))
  if (( m == 0 && s >= 30 )); then m=1; fi

  filled=$(( m * BAR_WIDTH / MAX_MIN ))
  (( filled > BAR_WIDTH )) && filled=$BAR_WIDTH
  (( m > 0 && filled == 0 )) && filled=1
  empty=$(( BAR_WIDTH - filled ))

  bar=""
  if (( filled > 0 )); then bar=$(printf '█%.0s' $(seq 1 "$filled")); fi
  if (( empty > 0 )); then bar+=$(printf '░%.0s' $(seq 1 "$empty")); fi

  short=$(echo "$day" | sed 's/^[0-9]*-//')
  if (( m > 0 )); then
    printf '  %s  %s  %dm\n' "$short" "$bar" "$m"
  else
    printf '  %s  %s  ·\n' "$short" "$bar"
  fi
done

echo
echo "💪 坚持下去，颈椎肩膀会感谢你。"
