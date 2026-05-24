#!/usr/bin/env bash
# claude-coach animation.sh
# 大画面、彩色、互动健身动画引擎（含 Claude 教练角色）。
# 用法: animation.sh <session_id> <runtime_file> <claude_pid> [pid_file]
# 兼容 bash 3.2（macOS 默认），完全程序化渲染，无外部帧文件。
# 防闪烁：alt screen buffer + 帧缓冲一次性 flush。

set -u

SESSION_ID="${1:-default}"
RUNTIME_FILE="${2:-}"
CLAUDE_PID="${3:-}"
PID_FILE="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

[[ -n "$PID_FILE" ]] && echo $$ > "$PID_FILE"

ACCUMULATED=0
LAST_FLUSH=0
FLUSH_INTERVAL=5
FRAME_IDX=0
FRAME_INTERVAL=0.2  # 5 fps

# ═══════════════════════════════════════════════════════
# 颜色 / ANSI 常量
# ═══════════════════════════════════════════════════════
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

ALT_SCREEN_ON="${ESC}[?1049h"
ALT_SCREEN_OFF="${ESC}[?1049l"
HIDE_CURSOR="${ESC}[?25l"
SHOW_CURSOR="${ESC}[?25h"

color_code() {
  case "$1" in
    red)     printf '%s' "${ESC}[31m";;
    green)   printf '%s' "${ESC}[32m";;
    yellow)  printf '%s' "${ESC}[33m";;
    blue)    printf '%s' "${ESC}[34m";;
    magenta) printf '%s' "${ESC}[35m";;
    cyan)    printf '%s' "${ESC}[36m";;
    white)   printf '%s' "${ESC}[37m";;
    bred)     printf '%s' "${ESC}[91m";;
    bgreen)   printf '%s' "${ESC}[92m";;
    byellow)  printf '%s' "${ESC}[93m";;
    bblue)    printf '%s' "${ESC}[94m";;
    bmagenta) printf '%s' "${ESC}[95m";;
    bcyan)    printf '%s' "${ESC}[96m";;
    *) printf '';;
  esac
}

# ═══════════════════════════════════════════════════════
# 帧缓冲（防闪烁核心）
# 所有 render 把内容写到 FRAME_BUF，render_screen 末尾一次性 flush
# ═══════════════════════════════════════════════════════
FRAME_BUF=""

buf_reset() {
  # 不用 2J 清屏 —— 那个会产生明显 flash。靠 alt screen + H 重定位 + 帧末 \033[J 清残留
  FRAME_BUF="${ESC}[H"
}

buf_flush() {
  # 帧末清掉光标以下的残留（之前更长帧的尾巴）
  FRAME_BUF+="${ESC}[J${RESET}"
  printf '%s' "$FRAME_BUF"
  FRAME_BUF=""
}

buf_at() {
  local row="$1" col="$2" color="$3" text="$4"
  local pos
  printf -v pos '%s[%d;%dH' "$ESC" "$row" "$col"
  FRAME_BUF+="$pos"
  if [[ -n "$color" ]]; then
    FRAME_BUF+="$(color_code "$color")"
  fi
  FRAME_BUF+="$text"
  FRAME_BUF+="$RESET"
}

buf_centered() {
  local row="$1" color="$2" text="$3"
  local len=${#text}
  local col=$(( (CACHED_COLS - len) / 2 + 1 ))
  (( col < 1 )) && col=1
  buf_at "$row" "$col" "$color" "$text"
}

# 清除特定行（避免上帧残留）
buf_clear_row() {
  local row="$1"
  local pos
  printf -v pos '%s[%d;1H%s[2K' "$ESC" "$row" "$ESC"
  FRAME_BUF+="$pos"
}

buf_clear_rows() {
  local from="$1" to="$2"
  local r
  for ((r=from; r<=to; r++)); do buf_clear_row "$r"; done
}

# ═══════════════════════════════════════════════════════
# 终端尺寸（每帧缓存一次）
# ═══════════════════════════════════════════════════════
CACHED_COLS=80
CACHED_LINES=24

refresh_term_size() {
  local size
  size=$(stty size 2>/dev/null) || size=""
  if [[ -n "$size" ]]; then
    CACHED_LINES=${size% *}
    CACHED_COLS=${size#* }
  fi
  # 兜底
  [[ -z "$CACHED_COLS" || "$CACHED_COLS" -lt 40 ]] && CACHED_COLS=80
  [[ -z "$CACHED_LINES" || "$CACHED_LINES" -lt 10 ]] && CACHED_LINES=24
}

# ═══════════════════════════════════════════════════════
# 大数字字体（5 行 × 5 列）
# ═══════════════════════════════════════════════════════
big_digit_row() {
  local d="$1" row="$2"
  case "$d:$row" in
    "0:0") echo " ███ ";; "0:1") echo "█   █";; "0:2") echo "█   █";; "0:3") echo "█   █";; "0:4") echo " ███ ";;
    "1:0") echo "  █  ";; "1:1") echo " ██  ";; "1:2") echo "  █  ";; "1:3") echo "  █  ";; "1:4") echo " ███ ";;
    "2:0") echo " ███ ";; "2:1") echo "█   █";; "2:2") echo "   █ ";; "2:3") echo " █   ";; "2:4") echo "█████";;
    "3:0") echo " ███ ";; "3:1") echo "█   █";; "3:2") echo "  ██ ";; "3:3") echo "█   █";; "3:4") echo " ███ ";;
    "4:0") echo "█   █";; "4:1") echo "█   █";; "4:2") echo "█████";; "4:3") echo "    █";; "4:4") echo "    █";;
    "5:0") echo "█████";; "5:1") echo "█    ";; "5:2") echo "████ ";; "5:3") echo "    █";; "5:4") echo "████ ";;
    "6:0") echo " ████";; "6:1") echo "█    ";; "6:2") echo "████ ";; "6:3") echo "█   █";; "6:4") echo " ███ ";;
    "7:0") echo "█████";; "7:1") echo "    █";; "7:2") echo "   █ ";; "7:3") echo "  █  ";; "7:4") echo "  █  ";;
    "8:0") echo " ███ ";; "8:1") echo "█   █";; "8:2") echo " ███ ";; "8:3") echo "█   █";; "8:4") echo " ███ ";;
    "9:0") echo " ███ ";; "9:1") echo "█   █";; "9:2") echo " ████";; "9:3") echo "    █";; "9:4") echo "████ ";;
    "::0") echo "     ";; "::1") echo "  █  ";; "::2") echo "     ";; "::3") echo "  █  ";; "::4") echo "     ";;
    *) printf '%-5s' " ";;
  esac
}

# 把数字串 s 渲染成 5 行，每行 5 字符 + 1 空格
big_text_lines() {
  local s="$1" row line c i
  for row in 0 1 2 3 4; do
    line=""
    for ((i=0; i<${#s}; i++)); do
      c="${s:$i:1}"
      line+="$(big_digit_row "$c" "$row") "
    done
    echo "$line"
  done
}

buf_big_text() {
  local row="$1" col="$2" color="$3" s="$4"
  local lines line lr=$row
  lines=$(big_text_lines "$s")
  while IFS= read -r line; do
    buf_at "$lr" "$col" "$color" "$line"
    lr=$((lr + 1))
  done <<< "$lines"
}

# ═══════════════════════════════════════════════════════
# 工具：杂项
# ═══════════════════════════════════════════════════════
format_duration() {
  local total_ms="${1:-0}"
  local total_s=$(( total_ms / 1000 ))
  local h=$(( total_s / 3600 ))
  local m=$(( (total_s % 3600) / 60 ))
  local s=$(( total_s % 60 ))
  printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

read_total_ms() {
  local stats; stats=$(cw_stats_file)
  [[ -f "$stats" ]] || { echo 0; return; }
  command -v jq >/dev/null 2>&1 || { echo 0; return; }
  jq -r '.total_ms // 0' "$stats" 2>/dev/null || echo 0
}

read_today_ms() {
  local stats; stats=$(cw_stats_file)
  [[ -f "$stats" ]] || { echo 0; return; }
  command -v jq >/dev/null 2>&1 || { echo 0; return; }
  local today; today=$(date +%Y-%m-%d)
  jq -r --arg d "$today" '.daily[$d] // 0' "$stats" 2>/dev/null || echo 0
}

# 横线生成（不用 for+printf 循环，效率高些）
make_line() {
  local n="$1" ch="$2"
  local line=""
  local i
  for ((i=0; i<n; i++)); do line+="$ch"; done
  echo "$line"
}

# ═══════════════════════════════════════════════════════
# Claude 教练角色
# ═══════════════════════════════════════════════════════
coach_pose_lines() {
  local idx="$1"
  case $((idx % 4)) in
    0) printf '%s\n' '     ✻' '   ╭───╮' '   │◕ ◕│' '   │ ▽ │' '   ╰─┬─╯' '    │ \';;
    1) printf '%s\n' '     ✻' '   ╭───╮' '   │^ ^│' '   │ ◡ │' '   ╰─┬─╯' '   /│';;
    2) printf '%s\n' '   ✻ ✻' '   ╭───╮' '   │◕ ◕│' '   │ ▽ │' '   ╰─┬─╯' '    │\\';;
    3) printf '%s\n' '   ✻' '   ╭───╮' '   │- -│' '   │ ◡ │' '   ╰─┬─╯' '    │/';;
  esac
}

coach_line_for() {
  local action="$1" frame="$2"
  local idx=$((frame % 4))
  case "$action" in
    eye-pursuit)   case $idx in 0) echo "眼睛跟着球~";; 1) echo "脖子别动!";; 2) echo "只动眼球";; 3) echo "做得真棒";; esac;;
    eye-saccade)   case $idx in 0) echo "啪! 切换!";; 1) echo "快速一点!";; 2) echo "眼神坚定";; 3) echo "节奏感真好";; esac;;
    eye-focus)     case $idx in 0) echo "看远处~";; 1) echo "现在看近!";; 2) echo "感受聚焦";; 3) echo "睫状肌在练";; esac;;
    finger-piano)  case $idx in 0) echo "弹琴啦~";; 1) echo "拇指对捏";; 2) echo "节奏!节奏!";; 3) echo "灵巧~";; esac;;
    finger-pose)   case $idx in 0) echo "变换造型";; 1) echo "做对动作";; 2) echo "手指灵活";; 3) echo "再来一个!";; esac;;
    shoulder-roll) case $idx in 0) echo "慢慢转动";; 1) echo "感受拉伸";; 2) echo "肩颈放松";; 3) echo "深呼吸~";; esac;;
    neck-side)     case $idx in 0) echo "耳贴肩膀";; 1) echo "保持住~";; 2) echo "感觉到了吗";; 3) echo "换边!";; esac;;
    breath-box)    case $idx in 0) echo "深~~~吸";; 1) echo "屏住";; 2) echo "慢~~~呼";; 3) echo "再屏住";; esac;;
    *) echo "加油!";;
  esac
}

draw_coach() {
  local start_col="$1" start_row="$2" action="$3" frame="$4"
  local pose_idx=$(( frame / 8 ))
  local line line_text
  local row=$start_row

  while IFS= read -r line; do
    buf_at "$row" "$start_col" "byellow" "$line"
    row=$((row + 1))
  done < <(coach_pose_lines "$pose_idx")

  line_text=$(coach_line_for "$action" "$((frame / 12))")

  local b_row=$((start_row + 1))
  local b_col=$((start_col + 16))
  buf_at "$b_row"          "$b_col" "bcyan" "╭──────────────╮"
  buf_at $((b_row + 1))    "$b_col" "bcyan" "│"
  buf_at $((b_row + 1))    "$((b_col + 2))" "bcyan" "${BOLD}${line_text}"
  buf_at $((b_row + 1))    "$((b_col + 15))" "bcyan" "│"
  buf_at $((b_row + 2))    "$b_col" "bcyan" "╰──────┬───────╯"
  buf_at $((b_row + 3))    "$b_col" "bcyan" "       ▽"
}

# ═══════════════════════════════════════════════════════
# 动作元数据 + 随机起点
# ═══════════════════════════════════════════════════════
ACTIONS=(eye-pursuit eye-saccade eye-focus finger-piano finger-pose shoulder-roll neck-side breath-box)
ACTION_DURATIONS=(60 20 20 40 30 30 40 32)
ACTION_COLORS=(bcyan bmagenta bblue bgreen green byellow magenta bcyan)

# 每次启动随机选起点，按固定顺序循环（仍能保证一轮覆盖全部 8 个动作）
START_OFFSET=$(( RANDOM % ${#ACTIONS[@]} ))

action_title_for() {
  case "$1" in
    eye-pursuit)   echo "平滑追踪眼动";;
    eye-saccade)   echo "跳视训练";;
    eye-focus)     echo "远近调焦";;
    finger-piano)  echo "手指钢琴";;
    finger-pose)   echo "手势造型";;
    shoulder-roll) echo "肩部画圆";;
    neck-side)     echo "颈侧屈伸";;
    breath-box)    echo "方框呼吸";;
    *) echo "$1";;
  esac
}

action_hint_for() {
  case "$1" in
    eye-pursuit)   echo "眼睛跟球，头不动";;
    eye-saccade)   echo "在两点间快速跳视";;
    eye-focus)     echo "近物 ↔ 远物切换";;
    finger-piano)  echo "拇指依次对捏其他指";;
    finger-pose)   echo "依次摆出 5 种造型";;
    shoulder-roll) echo "肩部画完整圆周";;
    neck-side)     echo "耳朵贴肩，左右各 5s";;
    breath-box)    echo "4-4-4-4 节拍呼吸";;
    *) echo "";;
  esac
}

# ═══════════════════════════════════════════════════════
# 动作 1: 平滑追踪眼动（抛球）
# ═══════════════════════════════════════════════════════
render_eye_pursuit() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local left_col=8
  local right_col=$((cols - 18))
  local figure_row=$((main_row + 3))

  local phase=$(( FRAME_IDX % 30 ))
  local t100
  if (( phase < 15 )); then
    t100=$(( phase * 100 / 15 ))
  else
    t100=$(( (30 - phase) * 100 / 15 ))
  fi
  local ball_col=$(( left_col + 4 + (right_col - left_col - 8) * t100 / 100 ))

  buf_at $((figure_row - 1)) "$left_col"  "yellow" "  ◯"
  buf_at "$figure_row"        "$left_col"  "yellow" " ╱│╲"
  buf_at $((figure_row + 1)) "$left_col"  "yellow" "  │"
  buf_at $((figure_row + 2)) "$left_col"  "yellow" " ╱ ╲"

  buf_at $((figure_row - 1)) "$right_col" "yellow" "  ◯"
  buf_at "$figure_row"        "$right_col" "yellow" " ╱│╲"
  buf_at $((figure_row + 1)) "$right_col" "yellow" "  │"
  buf_at $((figure_row + 2)) "$right_col" "yellow" " ╱ ╲"

  local arc_phase=$(( (phase % 15) * 100 / 15 ))
  local h=$(( arc_phase * (100 - arc_phase) / 25 ))
  local ball_row=$(( figure_row - 1 - h / 30 ))
  (( ball_row < main_row )) && ball_row=$main_row

  buf_at "$ball_row" "$ball_col" "bred" "●"
  buf_centered $((figure_row + 5)) "white" "↪ 眼睛跟着小球，头不要动 ↩"
}

# ═══════════════════════════════════════════════════════
# 动作 2: 跳视（saccade）
# ═══════════════════════════════════════════════════════
render_eye_saccade() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local left_col=10
  local right_col=$((cols - 14))
  local target_row=$((main_row + 4))
  local center=$((cols / 2))

  local active=$(( (FRAME_IDX / 5) % 2 ))

  if (( active == 0 )); then
    buf_at "$target_row" "$left_col"  "bred"  "◉ LEFT"
    buf_at "$target_row" "$right_col" "white" "◯ right"
    buf_at "$target_row" "$center"    "yellow" "⟵"
  else
    buf_at "$target_row" "$left_col"  "white" "◯ left"
    buf_at "$target_row" "$right_col" "bred"  "◉ RIGHT"
    buf_at "$target_row" "$center"    "yellow" "⟶"
  fi

  buf_centered $((target_row + 4)) "white" "啪! 啪! 眼球在两点间快速跳视"
}

# ═══════════════════════════════════════════════════════
# 动作 3: 远近调焦
# ═══════════════════════════════════════════════════════
render_eye_focus() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local mode=$(( (FRAME_IDX / 15) % 2 ))

  if (( mode == 0 )); then
    buf_at $((main_row + 2)) "$((center - 5))" "bgreen" "       NEAR"
    buf_at $((main_row + 4)) "$center" "bred" "•"
    buf_centered $((main_row + 6)) "white" "▸ 把目光聚到这个小点上"
  else
    buf_at $((main_row + 1)) "$((center - 13))" "bblue" "       F A R"
    buf_at $((main_row + 2)) "$((center - 13))" "blue"  "  ╭──────────────────╮"
    buf_at $((main_row + 3)) "$((center - 13))" "blue"  "  │                  │"
    buf_at $((main_row + 4)) "$((center - 13))" "blue"  "  │    ╲   /   /     │"
    buf_at $((main_row + 5)) "$((center - 13))" "blue"  "  │     ╲ / ╲ /      │"
    buf_at $((main_row + 6)) "$((center - 13))" "blue"  "  │      X   X       │"
    buf_at $((main_row + 7)) "$((center - 13))" "blue"  "  │     / ╲ / ╲      │"
    buf_at $((main_row + 8)) "$((center - 13))" "blue"  "  ╰──────────────────╯"
    buf_centered $((main_row + 10)) "white" "▸ 望向远方山林，放松眼肌"
  fi
}

# ═══════════════════════════════════════════════════════
# 动作 4: 手指钢琴
# ═══════════════════════════════════════════════════════
render_finger_piano() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local active=$(( (FRAME_IDX / 3) % 4 ))
  local names=("食指" "中指" "无名指" "小指")
  local labels=("1" "2" "3" "4")
  local hand_col=$((center - 12))
  local hand_row=$((main_row + 1))

  local i fcolor fchar
  for i in 0 1 2 3; do
    local col=$((hand_col + 6 + i * 5))
    if (( i == active )); then fcolor="bgreen"; fchar="█"; else fcolor="white"; fchar="│"; fi
    buf_at "$hand_row"        "$col" "$fcolor" " ╷  "
    buf_at $((hand_row + 1)) "$col" "$fcolor" " ${fchar}  "
    buf_at $((hand_row + 2)) "$col" "$fcolor" " ${fchar}  "
    buf_at $((hand_row + 3)) "$col" "$fcolor" " ${fchar}  "
    buf_at $((hand_row + 4)) "$col" "$fcolor" "${labels[$i]}    "
  done

  local thumb_col=$((hand_col + 6 + active * 5))
  buf_at $((hand_row + 5)) "$((thumb_col - 2))" "bred" "──◉"

  buf_at $((hand_row + 6)) "$hand_col" "yellow" "╭──────────────────────╮"
  buf_at $((hand_row + 7)) "$hand_col" "yellow" "│       手掌           │"
  buf_at $((hand_row + 8)) "$hand_col" "yellow" "╰──────────────────────╯"

  buf_centered $((hand_row + 10)) "bgreen" "▸ 拇指对捏 ${names[$active]}"
}

# ═══════════════════════════════════════════════════════
# 动作 5: 手势造型
# ═══════════════════════════════════════════════════════
render_finger_pose() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local pose=$(( (FRAME_IDX / 10) % 5 ))
  local art_row=$((main_row + 2))
  local art_col=$((center - 4))

  case $pose in
    0)
      buf_at "$art_row"        "$art_col" "yellow" "  ╭───╮  "
      buf_at $((art_row + 1)) "$art_col" "yellow" "  │ ◉ │  "
      buf_at $((art_row + 2)) "$art_col" "yellow" "  ╰───╯  "
      buf_at $((art_row + 3)) "$art_col" "yellow" "  ╲___╱  "
      buf_centered $((art_row + 5)) "bgreen" "✊ 握拳"
      ;;
    1)
      buf_at "$art_row"        "$art_col" "yellow" "  ╲╱╲╱  "
      buf_at $((art_row + 1)) "$art_col" "yellow" "  ││││  "
      buf_at $((art_row + 2)) "$art_col" "yellow" "  ╭──╮  "
      buf_at $((art_row + 3)) "$art_col" "yellow" "  │  │  "
      buf_centered $((art_row + 5)) "bgreen" "✋ 五指展开"
      ;;
    2)
      buf_at "$art_row"        "$art_col" "yellow" "  ╲   ╱  "
      buf_at $((art_row + 1)) "$art_col" "yellow" "   ╲ ╱   "
      buf_at $((art_row + 2)) "$art_col" "yellow" "    V    "
      buf_at $((art_row + 3)) "$art_col" "yellow" "   │ │   "
      buf_centered $((art_row + 5)) "bgreen" "✌  V 字"
      ;;
    3)
      buf_at "$art_row"        "$art_col" "yellow" "  ╭─╮    "
      buf_at $((art_row + 1)) "$art_col" "yellow" "  │○│ ▷  "
      buf_at $((art_row + 2)) "$art_col" "yellow" "  ╰─╯ │  "
      buf_at $((art_row + 3)) "$art_col" "yellow" "    ╲ │  "
      buf_centered $((art_row + 5)) "bgreen" "👌 OK 手势"
      ;;
    4)
      buf_at "$art_row"        "$art_col" "yellow" "    │   "
      buf_at $((art_row + 1)) "$art_col" "yellow" "    │   "
      buf_at $((art_row + 2)) "$art_col" "yellow" "    │   "
      buf_at $((art_row + 3)) "$art_col" "yellow" "    └─── "
      buf_centered $((art_row + 5)) "bgreen" "👍 L 形"
      ;;
  esac

  local dots="" p
  for p in 0 1 2 3 4; do
    if (( p == pose )); then dots+="● "; else dots+="○ "; fi
  done
  buf_centered $((art_row + 7)) "white" "$dots"
  buf_centered $((art_row + 9)) "white" "▸ 双手都做，2 秒一个造型"
}

# ═══════════════════════════════════════════════════════
# 动作 6: 肩部画圆
# ═══════════════════════════════════════════════════════
render_shoulder_roll() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local quadrant=$(( (FRAME_IDX / 7) % 4 ))
  local body_row=$((main_row + 1))
  local body_col=$((center - 10))

  buf_at "$body_row"          "$body_col" "white" "        ╭───╮"
  buf_at $((body_row + 1))   "$body_col" "white" "        │◕ ◕│"
  buf_at $((body_row + 2))   "$body_col" "white" "        ╰─┬─╯"

  case $quadrant in
    0)
      buf_at $((body_row + 1)) "$body_col" "bgreen" "↑↑"
      buf_at $((body_row + 1)) "$((body_col + 16))" "bgreen" "↑↑"
      buf_at $((body_row + 3)) "$body_col" "yellow" " ╔══════════════════╗"
      ;;
    1)
      buf_at $((body_row + 3)) "$body_col" "yellow" "◂════════════════════▸"
      ;;
    2)
      buf_at $((body_row + 3)) "$body_col" "yellow" " ╚══════════════════╝"
      buf_at $((body_row + 4)) "$body_col" "bgreen" "↓↓"
      buf_at $((body_row + 4)) "$((body_col + 16))" "bgreen" "↓↓"
      ;;
    3)
      buf_at $((body_row + 3)) "$body_col" "yellow" "▸════════════════════◂"
      ;;
  esac

  buf_at $((body_row + 4)) "$body_col" "white" "          │"
  buf_at $((body_row + 5)) "$body_col" "white" "          │"

  case $quadrant in
    0) buf_centered $((body_row + 7)) "bgreen" "▴ 肩上耸";;
    1) buf_centered $((body_row + 7)) "bgreen" "◂ 肩后展";;
    2) buf_centered $((body_row + 7)) "bgreen" "▾ 肩下沉";;
    3) buf_centered $((body_row + 7)) "bgreen" "▸ 肩前合";;
  esac
  buf_centered $((body_row + 9)) "yellow" "肩部慢慢画圆 ↻ "
}

# ═══════════════════════════════════════════════════════
# 动作 7: 颈侧屈
# ═══════════════════════════════════════════════════════
render_neck_side() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local cycle=$(( FRAME_IDX % 50 ))
  local side
  if (( cycle < 25 )); then side="left"; else side="right"; fi
  local body_row=$((main_row + 1))
  local body_col=$((center - 10))

  if [[ "$side" == "left" ]]; then
    buf_at "$body_row"          "$body_col" "white"  "    ╭───╮"
    buf_at $((body_row + 1))   "$body_col" "white"  "    │◕ ◕│"
    buf_at $((body_row + 2))   "$body_col" "white"  "    ╰─┬─╯"
    buf_at $((body_row + 3))   "$body_col" "bgreen" "   ╲"
    buf_at $((body_row + 4))   "$body_col" "yellow" "  ╔══════╗"
    buf_at $((body_row + 5))   "$body_col" "white"  "    │"
    buf_centered $((body_row + 7)) "bgreen" "◂ 左耳贴左肩（保持 5 秒）"
  else
    buf_at "$body_row"          "$body_col" "white"  "          ╭───╮"
    buf_at $((body_row + 1))   "$body_col" "white"  "          │◕ ◕│"
    buf_at $((body_row + 2))   "$body_col" "white"  "          ╰─┬─╯"
    buf_at $((body_row + 3))   "$body_col" "bgreen" "             ╱"
    buf_at $((body_row + 4))   "$body_col" "yellow" "       ╔══════╗"
    buf_at $((body_row + 5))   "$body_col" "white"  "          │"
    buf_centered $((body_row + 7)) "bgreen" "右耳贴右肩（保持 5 秒） ▸"
  fi

  local side_elapsed side_remain
  if [[ "$side" == "left" ]]; then side_elapsed=$cycle; else side_elapsed=$((cycle - 25)); fi
  side_remain=$(( 5 - side_elapsed / 5 ))
  (( side_remain < 0 )) && side_remain=0
  buf_centered $((body_row + 9)) "bred" "保持 ${side_remain}s"
}

# ═══════════════════════════════════════════════════════
# 动作 8: 方框呼吸
# ═══════════════════════════════════════════════════════
render_breath_box() {
  local main_row="$1"
  local cols=$CACHED_COLS
  local center=$((cols / 2))
  local box_w=24 box_h=8
  local box_col=$((center - box_w / 2))
  local box_row=$((main_row + 1))

  local cycle=$(( FRAME_IDX % 80 ))
  local phase=$(( cycle / 20 ))
  local phase_progress=$(( cycle % 20 ))
  local phase_names=("吸 气" "屏 住" "呼 气" "屏 住")
  local phase_colors=("bgreen" "byellow" "bcyan" "bmagenta")
  local pcolor="${phase_colors[$phase]}"

  local top="╔$(make_line $((box_w - 2)) '═')╗"
  local bot="╚$(make_line $((box_w - 2)) '═')╝"
  buf_at "$box_row" "$box_col" "$pcolor" "$top"
  local r
  for ((r=1; r<box_h-1; r++)); do
    buf_at $((box_row + r)) "$box_col" "$pcolor" "║"
    buf_at $((box_row + r)) $((box_col + box_w - 1)) "$pcolor" "║"
  done
  buf_at $((box_row + box_h - 1)) "$box_col" "$pcolor" "$bot"

  local cursor_row cursor_col
  case $phase in
    0) cursor_row=$box_row;                cursor_col=$(( box_col + 1 + (box_w - 3) * phase_progress / 19 ));;
    1) cursor_row=$(( box_row + 1 + (box_h - 3) * phase_progress / 19 )); cursor_col=$(( box_col + box_w - 1 ));;
    2) cursor_row=$(( box_row + box_h - 1 )); cursor_col=$(( box_col + box_w - 2 - (box_w - 3) * phase_progress / 19 ));;
    3) cursor_row=$(( box_row + box_h - 2 - (box_h - 3) * phase_progress / 19 )); cursor_col=$box_col;;
  esac
  buf_at "$cursor_row" "$cursor_col" "bred" "●"

  local stage_remain=$(( 4 - phase_progress / 5 ))
  (( stage_remain < 1 )) && stage_remain=1

  buf_at $((box_row + 2)) $((box_col + 8)) "$pcolor" "${BOLD}${phase_names[$phase]}"
  buf_big_text $((box_row + 3)) $((box_col + 10)) "$pcolor" "$stage_remain"
  buf_centered $((box_row + box_h + 1)) "white" "▸ 跟随光标和大数字呼吸"
}

# ═══════════════════════════════════════════════════════
# 分发
# ═══════════════════════════════════════════════════════
render_dispatch() {
  local action="$1" main_row="$2"
  case "$action" in
    eye-pursuit)   render_eye_pursuit   "$main_row";;
    eye-saccade)   render_eye_saccade   "$main_row";;
    eye-focus)     render_eye_focus     "$main_row";;
    finger-piano)  render_finger_piano  "$main_row";;
    finger-pose)   render_finger_pose   "$main_row";;
    shoulder-roll) render_shoulder_roll "$main_row";;
    neck-side)     render_neck_side     "$main_row";;
    breath-box)    render_breath_box    "$main_row";;
  esac
}

render_screen() {
  local action="$1" action_idx="$2" elapsed="$3" duration="$4" color="$5"

  refresh_term_size
  local cols=$CACHED_COLS
  local lines=$CACHED_LINES
  local title; title=$(action_title_for "$action")
  local hint;  hint=$(action_hint_for "$action")
  local remain=$(( duration - elapsed ))
  (( remain < 0 )) && remain=0

  buf_reset

  # 顶部清行 + 标题栏
  buf_clear_rows 1 2
  local header_text=" Claude Coach · $((action_idx + 1))/${#ACTIONS[@]} · $title · $hint "
  buf_at 1 1 "$color" "${BOLD}${header_text}"
  buf_at 2 1 "$color" "$(make_line "$cols" '═')"

  # 主动画区清行（4 .. lines-4）
  buf_clear_rows 3 $((lines - 4))
  render_dispatch "$action" 4

  # 教练（足够宽时在右上，否则不画）
  if (( cols >= 100 )); then
    draw_coach $(( cols - 36 )) 5 "$action" "$FRAME_IDX"
  elif (( cols >= 80 )); then
    # 中等宽度：教练放主动画区下方
    draw_coach 3 $((lines - 11)) "$action" "$FRAME_IDX"
  fi

  # 大数字倒计时（仅 cols>=100 && lines>=28 才显示）
  if (( cols >= 100 && lines >= 28 )); then
    local big_row=$((lines - 9))
    local big_col=4
    buf_at "$big_row" "$big_col" "byellow" "${BOLD}剩余"
    buf_big_text $((big_row + 1)) "$big_col" "byellow" "$remain"
    buf_at $((big_row + 7)) "$big_col" "yellow" "  秒"
  else
    buf_at 1 $((cols - 14)) "byellow" "${BOLD}剩余 ${remain}s "
  fi

  # 底部清行 + 进度条 + 统计
  buf_clear_rows $((lines - 2)) "$lines"
  local bar_width=$((cols - 4))
  local filled=$(( elapsed * bar_width / (duration > 0 ? duration : 1) ))
  (( filled < 0 )) && filled=0
  (( filled > bar_width )) && filled=$bar_width
  local empty=$(( bar_width - filled ))

  local fbar; fbar=$(make_line "$filled" '█')
  local ebar; ebar=$(make_line "$empty" '░')
  buf_at $((lines - 2)) 2 "$color" "$fbar"
  buf_at $((lines - 2)) $((2 + filled)) "" "${DIM}${ebar}${RESET}"

  local total_ms today_ms session_ms
  total_ms=$(read_total_ms)
  today_ms=$(read_today_ms)
  session_ms=$(( ACCUMULATED * 1000 ))
  buf_at "$lines" 2 "" "${DIM}总累计${RESET} $(format_duration "$total_ms")   ${DIM}今日${RESET} $(format_duration "$today_ms")   ${DIM}本次${RESET} $(format_duration "$session_ms")   ${DIM}✻ Claude Coach${RESET}"

  buf_flush
}

# ═══════════════════════════════════════════════════════
# 启停 + 清理
# ═══════════════════════════════════════════════════════
flush_stats() {
  local now=$1
  local delta=$(( now - LAST_FLUSH ))
  (( delta <= 0 )) && return
  cw_update_stats "$delta"
  cw_update_session_ms "$RUNTIME_FILE" "$(( ACCUMULATED * 1000 ))"
  LAST_FLUSH=$now
}

cleanup() {
  local now=$SECONDS
  ACCUMULATED=$now
  flush_stats "$now"
  printf '%s%s' "$ALT_SCREEN_OFF" "$SHOW_CURSOR"
  printf '\n\n        '
  printf '%s╭──────────────────────╮\n' "$(color_code cyan)"
  printf '        │   %s✻ 辛苦了，做得真棒%s%s   │\n' "$(color_code yellow)" "$RESET" "$(color_code cyan)"
  printf '        ╰──────────────────────╯%s\n\n' "$RESET"
  printf '        本次运动 %s%d%s 秒\n' "${BOLD}$(color_code yellow)" "$now" "$RESET"
  sleep 0.3
  exit 0
}
trap cleanup TERM INT HUP

# 进入 alt screen + 隐藏光标
printf '%s%s' "$ALT_SCREEN_ON" "$HIDE_CURSOR"

# ═══════════════════════════════════════════════════════
# 主循环
# ═══════════════════════════════════════════════════════
SECONDS=0
while :; do
  ai_raw=0
  while (( ai_raw < ${#ACTIONS[@]} )); do
    ai=$(( (ai_raw + START_OFFSET) % ${#ACTIONS[@]} ))
    action="${ACTIONS[$ai]}"
    duration="${ACTION_DURATIONS[$ai]}"
    color="${ACTION_COLORS[$ai]}"
    action_start=$SECONDS

    while :; do
      elapsed=$(( SECONDS - action_start ))
      (( elapsed >= duration )) && break

      render_screen "$action" "$ai" "$elapsed" "$duration" "$color"

      sleep "$FRAME_INTERVAL"
      FRAME_IDX=$((FRAME_IDX + 1))

      ACCUMULATED=$SECONDS
      now=$SECONDS
      if (( now - LAST_FLUSH >= FLUSH_INTERVAL )); then
        flush_stats "$now"
      fi
    done

    ai_raw=$((ai_raw + 1))
    FRAME_IDX=0
  done
done
