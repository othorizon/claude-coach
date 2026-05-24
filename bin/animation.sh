#!/usr/bin/env bash
# claude-coach animation.sh
# 大画面、彩色、互动健身动画引擎
# 布局：顶部 BIG BANNER + 中央 CANVAS + 右侧 BIG OCTOPUS + 右下 BUDDY
# 用法: animation.sh <session_id> <runtime_file> <claude_pid> [pid_file]
# 兼容 bash 3.2（macOS 默认）。

set -u

SESSION_ID="${1:-default}"
RUNTIME_FILE="${2:-}"
CLAUDE_PID="${3:-}"
PID_FILE="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/buddy.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/banner.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/octopus_big.sh"

[[ -n "$PID_FILE" ]] && echo $$ > "$PID_FILE"

ACCUMULATED=0
LAST_FLUSH=0
FLUSH_INTERVAL=5
FRAME_IDX=0
FRAME_INTERVAL=0.2
SELF_CHECK_INTERVAL=10

# ═══════════════════════════════════════════════════════
# ANSI 常量
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
# 帧缓冲
# ═══════════════════════════════════════════════════════
FRAME_BUF=""

buf_reset() { FRAME_BUF="${ESC}[H"; }

buf_flush() {
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
# 终端尺寸
# ═══════════════════════════════════════════════════════
CACHED_COLS=120
CACHED_LINES=32

refresh_term_size() {
  local size
  size=$(stty size 2>/dev/null) || size=""
  if [[ -n "$size" ]]; then
    CACHED_LINES=${size% *}
    CACHED_COLS=${size#* }
  fi
  [[ -z "$CACHED_COLS" || "$CACHED_COLS" -lt 40 ]] && CACHED_COLS=120
  [[ -z "$CACHED_LINES" || "$CACHED_LINES" -lt 10 ]] && CACHED_LINES=32
}

# ═══════════════════════════════════════════════════════
# 工具
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

make_line() {
  local n="$1" ch="$2"
  local line=""
  local i
  for ((i=0; i<n; i++)); do line+="$ch"; done
  echo "$line"
}

# ═══════════════════════════════════════════════════════
# 本会话的 buddy 角色 + 眼睛（session_id hash 决定，固定不变）
# ═══════════════════════════════════════════════════════
BUDDY_SPECIES_CURRENT=$(buddy_for_session "$SESSION_ID")
BUDDY_EYE_CURRENT=$(buddy_eye_for_session "$SESSION_ID")
BUDDY_NAME=$(buddy_chinese_name "$BUDDY_SPECIES_CURRENT")

# 动作元数据
ACTIONS=(eye-track eye-saccade finger-piano finger-pose shoulder-roll neck-side breath-box)
ACTION_DURATIONS=(60 20 40 30 30 40 32)
ACTION_COLORS=(bcyan bmagenta bgreen green byellow magenta bcyan)

# 大字 banner 名（英文，给字体识别用）
ACTION_BANNERS=(
  "EYE TRACK"
  "SACCADE"
  "FINGERS"
  "HAND POSE"
  "SHOULDER"
  "NECK SIDE"
  "BREATHE"
)

START_OFFSET=$(( RANDOM % ${#ACTIONS[@]} ))

action_title_for() {
  case "$1" in
    eye-track)     echo "眼神追踪";;
    eye-saccade)   echo "跳视训练";;
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
    eye-track)     echo "跟着大章鱼眼神看四方";;
    eye-saccade)   echo "眼球在两点间快速跳视";;
    finger-piano)  echo "拇指依次对捏其他指";;
    finger-pose)   echo "依次摆出 5 种造型";;
    shoulder-roll) echo "肩部画完整圆周";;
    neck-side)     echo "耳朵贴肩，左右各 5s";;
    breath-box)    echo "4-4-4-4 节拍呼吸";;
    *) echo "";;
  esac
}

# ═══════════════════════════════════════════════════════
# Coach 教练台词
# ═══════════════════════════════════════════════════════
coach_line_for() {
  local action="$1" frame="$2"
  local idx=$((frame % 4))
  case "$action" in
    eye-track)     case $idx in 0) echo "跟我看~";;  1) echo "头别动!";;  2) echo "只动眼球";; 3) echo "做得棒!";; esac;;
    eye-saccade)   case $idx in 0) echo "啪!切换!";; 1) echo "快一点!";;  2) echo "眼神坚定";; 3) echo "节奏感~";; esac;;
    finger-piano)  case $idx in 0) echo "弹琴啦~";;  1) echo "拇指对捏";;  2) echo "节奏!";;    3) echo "灵巧~";;   esac;;
    finger-pose)   case $idx in 0) echo "变造型!";;  1) echo "做对动作";;  2) echo "手指灵活";; 3) echo "再来!";;   esac;;
    shoulder-roll) case $idx in 0) echo "慢慢转";;   1) echo "感受拉伸";;  2) echo "肩颈放松";; 3) echo "深呼吸~";; esac;;
    neck-side)     case $idx in 0) echo "耳贴肩";;   1) echo "保持住~";;  2) echo "感觉到没";; 3) echo "换边!";;   esac;;
    breath-box)    case $idx in 0) echo "深~吸";;    1) echo "屏住";;      2) echo "慢~呼";;    3) echo "再屏住";;  esac;;
    *) echo "加油!";;
  esac
}

# 把 buddy + 气泡画在右下角
# 气泡尾巴向左指向 buddy（buddy 在气泡右下方）
draw_buddy_with_bubble() {
  local base_row="$1" base_col="$2" action="$3" frame="$4" color="$5"

  # buddy 帧：每 4 帧切一帧
  local buddy_frame_idx=$(( (frame / 4) % 3 ))
  draw_buddy_at "$BUDDY_SPECIES_CURRENT" "$buddy_frame_idx" "$BUDDY_EYE_CURRENT" \
                "$base_row" "$base_col" "$color"

  # 气泡：在 buddy 的右边
  local line_text; line_text=$(coach_line_for "$action" "$((frame / 12))")
  local b_col=$((base_col + 14))
  local b_row=$base_row
  buf_at "$b_row"           "$b_col" "$color" "╭──────────╮"
  buf_at "$((b_row + 1))"   "$b_col" "$color" "│"
  buf_at "$((b_row + 1))"   "$((b_col + 2))" "$color" "${BOLD}${line_text}"
  buf_at "$((b_row + 1))"   "$((b_col + 11))" "$color" "│"
  buf_at "$((b_row + 2))"   "$b_col" "$color" "╰─◁────────╯"

  # buddy 名字
  buf_at "$((base_row + 5))" "$base_col" "white" "${DIM}${BUDDY_NAME}${RESET}"
}

# ═══════════════════════════════════════════════════════
# Canvas 渲染：大字符动画
# 画布区域：cols 2 .. CANVAS_RIGHT，rows CANVAS_TOP .. CANVAS_BOTTOM
# ═══════════════════════════════════════════════════════
CANVAS_LEFT=2
CANVAS_RIGHT=82      # 之后会按 cols 动态调整
CANVAS_TOP=10
CANVAS_BOTTOM=24

# 中心点
canvas_center_col() { echo $(( (CANVAS_LEFT + CANVAS_RIGHT) / 2 )); }
canvas_center_row() { echo $(( (CANVAS_TOP + CANVAS_BOTTOM) / 2 )); }

# ─────────────────────────────────────────────────────
# 动作 1: eye-track 眼神追踪
# 画一个超大的方向箭头 + 大字 LOOK xxx
# 序列：center → up → center → right → center → down → center → left
# ─────────────────────────────────────────────────────
EYE_TRACK_SEQUENCE=(center up center right center down center left)

# 画大箭头（指向 dir：up/down/left/right），中心位置 (r, c)
draw_big_arrow() {
  local dir="$1" r="$2" c="$3" color="$4"
  case "$dir" in
    up)
      buf_at "$r"           "$c"     "$color" "        ▲▲        "
      buf_at "$((r + 1))"   "$c"     "$color" "      ▲▲▲▲▲▲      "
      buf_at "$((r + 2))"   "$c"     "$color" "    ▲▲▲▲▲▲▲▲▲▲    "
      buf_at "$((r + 3))"   "$c"     "$color" "  ▲▲▲▲▲▲▲▲▲▲▲▲▲▲  "
      buf_at "$((r + 4))"   "$c"     "$color" "▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲"
      buf_at "$((r + 5))"   "$c"     "$color" "      ██████      "
      buf_at "$((r + 6))"   "$c"     "$color" "      ██████      "
      buf_at "$((r + 7))"   "$c"     "$color" "      ██████      "
      ;;
    down)
      buf_at "$r"           "$c"     "$color" "      ██████      "
      buf_at "$((r + 1))"   "$c"     "$color" "      ██████      "
      buf_at "$((r + 2))"   "$c"     "$color" "      ██████      "
      buf_at "$((r + 3))"   "$c"     "$color" "▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼"
      buf_at "$((r + 4))"   "$c"     "$color" "  ▼▼▼▼▼▼▼▼▼▼▼▼▼▼  "
      buf_at "$((r + 5))"   "$c"     "$color" "    ▼▼▼▼▼▼▼▼▼▼    "
      buf_at "$((r + 6))"   "$c"     "$color" "      ▼▼▼▼▼▼      "
      buf_at "$((r + 7))"   "$c"     "$color" "        ▼▼        "
      ;;
    left)
      buf_at "$r"           "$c"     "$color" "         ◀        "
      buf_at "$((r + 1))"   "$c"     "$color" "       ◀◀◀        "
      buf_at "$((r + 2))"   "$c"     "$color" "     ◀◀◀◀◀████████"
      buf_at "$((r + 3))"   "$c"     "$color" "   ◀◀◀◀◀◀◀████████"
      buf_at "$((r + 4))"   "$c"     "$color" " ◀◀◀◀◀◀◀◀◀████████"
      buf_at "$((r + 5))"   "$c"     "$color" "   ◀◀◀◀◀◀◀████████"
      buf_at "$((r + 6))"   "$c"     "$color" "     ◀◀◀◀◀████████"
      buf_at "$((r + 7))"   "$c"     "$color" "       ◀◀◀        "
      ;;
    right)
      buf_at "$r"           "$c"     "$color" "        ▶         "
      buf_at "$((r + 1))"   "$c"     "$color" "        ▶▶▶       "
      buf_at "$((r + 2))"   "$c"     "$color" "████████▶▶▶▶▶     "
      buf_at "$((r + 3))"   "$c"     "$color" "████████▶▶▶▶▶▶▶   "
      buf_at "$((r + 4))"   "$c"     "$color" "████████▶▶▶▶▶▶▶▶▶ "
      buf_at "$((r + 5))"   "$c"     "$color" "████████▶▶▶▶▶▶▶   "
      buf_at "$((r + 6))"   "$c"     "$color" "████████▶▶▶▶▶     "
      buf_at "$((r + 7))"   "$c"     "$color" "        ▶▶▶       "
      ;;
    center)
      buf_at "$r"           "$c"     "$color" "                  "
      buf_at "$((r + 1))"   "$c"     "$color" "    ╭──────────╮  "
      buf_at "$((r + 2))"   "$c"     "$color" "    │          │  "
      buf_at "$((r + 3))"   "$c"     "$color" "    │   ◉◉◉    │  "
      buf_at "$((r + 4))"   "$c"     "$color" "    │  ◉████◉   │  "
      buf_at "$((r + 5))"   "$c"     "$color" "    │   ◉◉◉    │  "
      buf_at "$((r + 6))"   "$c"     "$color" "    │          │  "
      buf_at "$((r + 7))"   "$c"     "$color" "    ╰──────────╯  "
      ;;
  esac
}

render_eye_track() {
  local cc=$(canvas_center_col)
  local pos_idx=$(( (FRAME_IDX / 10) % ${#EYE_TRACK_SEQUENCE[@]} ))
  local current="${EYE_TRACK_SEQUENCE[$pos_idx]}"

  # 大字提示：UP/DOWN/LEFT/RIGHT/HERE
  local label
  case "$current" in
    up)     label="LOOK UP";;
    down)   label="LOOK DOWN";;
    left)   label="LOOK LEFT";;
    right)  label="LOOK RIGHT";;
    center) label="FOCUS";;
  esac

  # 大箭头放在 canvas 上半部分
  local arrow_r=$((CANVAS_TOP + 2))
  local arrow_c=$(( cc - 9 ))
  draw_big_arrow "$current" "$arrow_r" "$arrow_c" "bgreen"

  # 中文提示在最下方
  local hint_r=$((CANVAS_BOTTOM - 1))
  buf_centered "$hint_r" "byellow" "▸ 头不动，眼睛跟着大章鱼的视线方向"
  buf_centered "$((hint_r - 1))" "white" "${DIM}方向: ${label}${RESET}"
}

# ─────────────────────────────────────────────────────
# 动作 2: eye-saccade 跳视
# 两个大目标交替闪烁，中间有大箭头
# ─────────────────────────────────────────────────────
render_eye_saccade() {
  local cc=$(canvas_center_col)
  local cr=$(canvas_center_row)
  local target_size=8

  local active=$(( (FRAME_IDX / 5) % 2 ))

  local left_c=$(( CANVAS_LEFT + 4 ))
  local right_c=$(( CANVAS_RIGHT - 12 ))
  local target_r=$(( cr - 2 ))

  # 左目标
  local lcolor="white"
  local lchar="◯"
  if (( active == 0 )); then lcolor="bred"; lchar="◉"; fi
  buf_at "$target_r"        "$left_c" "$lcolor" "╔══════╗"
  buf_at "$((target_r + 1))" "$left_c" "$lcolor" "║      ║"
  buf_at "$((target_r + 2))" "$left_c" "$lcolor" "║  $lchar   ║"
  buf_at "$((target_r + 3))" "$left_c" "$lcolor" "║      ║"
  buf_at "$((target_r + 4))" "$left_c" "$lcolor" "╚══════╝"
  buf_at "$((target_r + 5))" "$left_c" "$lcolor" " LEFT  "

  # 右目标
  local rcolor="white"
  local rchar="◯"
  if (( active == 1 )); then rcolor="bred"; rchar="◉"; fi
  buf_at "$target_r"        "$right_c" "$rcolor" "╔══════╗"
  buf_at "$((target_r + 1))" "$right_c" "$rcolor" "║      ║"
  buf_at "$((target_r + 2))" "$right_c" "$rcolor" "║  $rchar   ║"
  buf_at "$((target_r + 3))" "$right_c" "$rcolor" "║      ║"
  buf_at "$((target_r + 4))" "$right_c" "$rcolor" "╚══════╝"
  buf_at "$((target_r + 5))" "$right_c" "$rcolor" " RIGHT "

  # 中央指示箭头
  local mid_c=$(( cc - 5 ))
  if (( active == 0 )); then
    buf_at "$((target_r + 1))" "$mid_c" "yellow" "          "
    buf_at "$((target_r + 2))" "$mid_c" "byellow" "    ◀◀◀   "
    buf_at "$((target_r + 3))" "$mid_c" "byellow" "  ◀◀◀◀◀   "
    buf_at "$((target_r + 4))" "$mid_c" "byellow" "    ◀◀◀   "
  else
    buf_at "$((target_r + 1))" "$mid_c" "yellow" "          "
    buf_at "$((target_r + 2))" "$mid_c" "byellow" "   ▶▶▶    "
    buf_at "$((target_r + 3))" "$mid_c" "byellow" "   ▶▶▶▶▶  "
    buf_at "$((target_r + 4))" "$mid_c" "byellow" "   ▶▶▶    "
  fi

  buf_centered "$((CANVAS_BOTTOM - 1))" "byellow" "▸ 啪! 啪! 眼球在两点间快速切换"
}

# ─────────────────────────────────────────────────────
# 动作 3: finger-piano 手指钢琴
# 一只大手（手掌 + 5 指），轮流高亮要对捏的指头
# ─────────────────────────────────────────────────────
render_finger_piano() {
  local cc=$(canvas_center_col)
  local active=$(( (FRAME_IDX / 3) % 4 ))
  local labels=("INDEX" "MIDDLE" "RING" "PINKY")
  local cn_names=("食指" "中指" "无名指" "小指")
  local finger_x=( $(( cc - 24 )) $(( cc - 12 )) $(( cc )) $(( cc + 12 )) )

  local top_r=$((CANVAS_TOP + 1))

  # 4 个手指（不含拇指）
  local i col fc fchar
  for i in 0 1 2 3; do
    col=${finger_x[$i]}
    if (( i == active )); then fc="bgreen"; fchar="█"; else fc="white"; fchar="│"; fi
    buf_at "$top_r"           "$col" "$fc" "┌──┐"
    buf_at "$((top_r + 1))"   "$col" "$fc" "│${fchar}${fchar}│"
    buf_at "$((top_r + 2))"   "$col" "$fc" "│${fchar}${fchar}│"
    buf_at "$((top_r + 3))"   "$col" "$fc" "│${fchar}${fchar}│"
    buf_at "$((top_r + 4))"   "$col" "$fc" "│${fchar}${fchar}│"
    buf_at "$((top_r + 5))"   "$col" "$fc" "└┬┬┘"
    buf_at "$((top_r + 6))"   "$col" "$fc" " ${labels[$i]:0:2} "
  done

  # 手掌
  local palm_r=$((top_r + 7))
  local palm_c=$(( cc - 26 ))
  local palm_w=44
  buf_at "$palm_r"          "$palm_c" "yellow" "╭$(make_line $((palm_w - 2)) '─')╮"
  buf_at "$((palm_r + 1))"  "$palm_c" "yellow" "│$(make_line $((palm_w - 2)) ' ')│"
  buf_at "$((palm_r + 1))"  "$((palm_c + palm_w / 2 - 6))" "yellow" "${BOLD}PALM 手掌"
  buf_at "$((palm_r + 2))"  "$palm_c" "yellow" "│$(make_line $((palm_w - 2)) ' ')│"
  buf_at "$((palm_r + 3))"  "$palm_c" "yellow" "╰$(make_line $((palm_w - 2)) '─')╯"

  # 拇指（在手掌左下方），有"对捏"动作箭头指向 active 手指
  local thumb_r=$((palm_r + 2))
  local thumb_c=$(( palm_c + 2 ))
  buf_at "$thumb_r"         "$thumb_c" "bred" "👍THUMB"
  local target_col=${finger_x[$active]}
  buf_at "$((palm_r - 1))"  "$thumb_c" "bred" "$(make_line $((target_col - thumb_c)) '─')◉"

  # 状态
  buf_centered "$((CANVAS_BOTTOM - 1))" "bgreen" "▸ 拇指对捏 ${cn_names[$active]} (${labels[$active]})"
}

# ─────────────────────────────────────────────────────
# 动作 4: finger-pose 手势造型
# 5 种大手势，每 2 秒切一个
# ─────────────────────────────────────────────────────
render_finger_pose() {
  local cc=$(canvas_center_col)
  local pose=$(( (FRAME_IDX / 10) % 5 ))
  local art_r=$((CANVAS_TOP + 1))
  local art_c=$(( cc - 10 ))

  # 每个姿势 12 行 × 20 字符
  case $pose in
    0)  # 握拳 FIST
      buf_at "$art_r"           "$art_c" "yellow" "         FIST"
      buf_at "$((art_r + 1))"   "$art_c" "yellow" ""
      buf_at "$((art_r + 2))"   "$art_c" "yellow" "       ╭─────╮"
      buf_at "$((art_r + 3))"   "$art_c" "yellow" "       │ ███ │"
      buf_at "$((art_r + 4))"   "$art_c" "yellow" "       │█████│"
      buf_at "$((art_r + 5))"   "$art_c" "yellow" "       │█████│"
      buf_at "$((art_r + 6))"   "$art_c" "yellow" "       │█████│"
      buf_at "$((art_r + 7))"   "$art_c" "yellow" "       │ ███ │"
      buf_at "$((art_r + 8))"   "$art_c" "yellow" "       ╰──┬──╯"
      buf_at "$((art_r + 9))"   "$art_c" "yellow" "          │"
      buf_at "$((art_r + 10))"  "$art_c" "yellow" "       ━━━━━━━"
      buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "✊  握拳"
      ;;
    1)  # 五指展开 OPEN HAND
      buf_at "$art_r"           "$art_c" "yellow" "      OPEN HAND"
      buf_at "$((art_r + 1))"   "$art_c" "yellow" ""
      buf_at "$((art_r + 2))"   "$art_c" "yellow" "     █ █ █ █ █"
      buf_at "$((art_r + 3))"   "$art_c" "yellow" "     █ █ █ █ █"
      buf_at "$((art_r + 4))"   "$art_c" "yellow" "     █ █ █ █ █"
      buf_at "$((art_r + 5))"   "$art_c" "yellow" "     █ █ █ █ █"
      buf_at "$((art_r + 6))"   "$art_c" "yellow" "     ╭───────╮"
      buf_at "$((art_r + 7))"   "$art_c" "yellow" "     │███████│"
      buf_at "$((art_r + 8))"   "$art_c" "yellow" "     │███████│"
      buf_at "$((art_r + 9))"   "$art_c" "yellow" "     ╰───┬───╯"
      buf_at "$((art_r + 10))"  "$art_c" "yellow" "        │"
      buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "✋  五指展开"
      ;;
    2)  # V 字
      buf_at "$art_r"           "$art_c" "yellow" "      V SIGN"
      buf_at "$((art_r + 1))"   "$art_c" "yellow" ""
      buf_at "$((art_r + 2))"   "$art_c" "yellow" "      ██   ██"
      buf_at "$((art_r + 3))"   "$art_c" "yellow" "      ██   ██"
      buf_at "$((art_r + 4))"   "$art_c" "yellow" "      ██   ██"
      buf_at "$((art_r + 5))"   "$art_c" "yellow" "       ██ ██"
      buf_at "$((art_r + 6))"   "$art_c" "yellow" "        ███"
      buf_at "$((art_r + 7))"   "$art_c" "yellow" "     ╭───────╮"
      buf_at "$((art_r + 8))"   "$art_c" "yellow" "     │███████│"
      buf_at "$((art_r + 9))"   "$art_c" "yellow" "     ╰───┬───╯"
      buf_at "$((art_r + 10))"  "$art_c" "yellow" "        │"
      buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "✌  V 字"
      ;;
    3)  # OK
      buf_at "$art_r"           "$art_c" "yellow" "       OK SIGN"
      buf_at "$((art_r + 1))"   "$art_c" "yellow" ""
      buf_at "$((art_r + 2))"   "$art_c" "yellow" "              █"
      buf_at "$((art_r + 3))"   "$art_c" "yellow" "              █"
      buf_at "$((art_r + 4))"   "$art_c" "yellow" "       ╭───╮ █"
      buf_at "$((art_r + 5))"   "$art_c" "yellow" "       │   │█"
      buf_at "$((art_r + 6))"   "$art_c" "yellow" "       │ ◯ │"
      buf_at "$((art_r + 7))"   "$art_c" "yellow" "       │   │"
      buf_at "$((art_r + 8))"   "$art_c" "yellow" "       ╰─┬─╯"
      buf_at "$((art_r + 9))"   "$art_c" "yellow" "    ╭─────────╮"
      buf_at "$((art_r + 10))"  "$art_c" "yellow" "    │█████████│"
      buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "👌  OK 手势"
      ;;
    4)  # L
      buf_at "$art_r"           "$art_c" "yellow" "       L SHAPE"
      buf_at "$((art_r + 1))"   "$art_c" "yellow" ""
      buf_at "$((art_r + 2))"   "$art_c" "yellow" "       ██"
      buf_at "$((art_r + 3))"   "$art_c" "yellow" "       ██"
      buf_at "$((art_r + 4))"   "$art_c" "yellow" "       ██"
      buf_at "$((art_r + 5))"   "$art_c" "yellow" "       ██████████"
      buf_at "$((art_r + 6))"   "$art_c" "yellow" "       ██"
      buf_at "$((art_r + 7))"   "$art_c" "yellow" "     ╭─────────╮"
      buf_at "$((art_r + 8))"   "$art_c" "yellow" "     │█████████│"
      buf_at "$((art_r + 9))"   "$art_c" "yellow" "     ╰────┬────╯"
      buf_at "$((art_r + 10))"  "$art_c" "yellow" "          │"
      buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "👍  L 形"
      ;;
  esac

  # 进度点
  local dots="" p
  for p in 0 1 2 3 4; do
    if (( p == pose )); then dots+="●  "; else dots+="○  "; fi
  done
  buf_centered "$((CANVAS_BOTTOM - 1))" "white" "$dots"
}

# ─────────────────────────────────────────────────────
# 动作 5: shoulder-roll 肩部画圆
# 大人形上半身，肩部按 上→后→下→前 节奏画圆，加圆周轨迹
# ─────────────────────────────────────────────────────
render_shoulder_roll() {
  local cc=$(canvas_center_col)
  local quadrant=$(( (FRAME_IDX / 7) % 4 ))
  local body_r=$((CANVAS_TOP + 1))
  local body_c=$(( cc - 15 ))

  # 大头
  buf_at "$body_r"          "$body_c" "white"  "            ╔═══════════╗"
  buf_at "$((body_r + 1))"  "$body_c" "white"  "            ║   ◕   ◕   ║"
  buf_at "$((body_r + 2))"  "$body_c" "white"  "            ║     ω     ║"
  buf_at "$((body_r + 3))"  "$body_c" "white"  "            ║   ─────   ║"
  buf_at "$((body_r + 4))"  "$body_c" "white"  "            ╚═════╤═════╝"
  buf_at "$((body_r + 5))"  "$body_c" "white"  "                  │"

  # 肩膀位置（按 quadrant 上/下移动 + 左右）
  local lshoulder_r rshoulder_r lshoulder_c rshoulder_c
  case $quadrant in
    0)  # UP - 肩耸起
      lshoulder_r=$((body_r + 4)); rshoulder_r=$((body_r + 4))
      lshoulder_c=$((body_c + 6));  rshoulder_c=$((body_c + 22))
      ;;
    1)  # BACK - 肩往后展（图示用宽展）
      lshoulder_r=$((body_r + 6)); rshoulder_r=$((body_r + 6))
      lshoulder_c=$((body_c + 2));  rshoulder_c=$((body_c + 26))
      ;;
    2)  # DOWN - 肩下沉
      lshoulder_r=$((body_r + 8)); rshoulder_r=$((body_r + 8))
      lshoulder_c=$((body_c + 6));  rshoulder_c=$((body_c + 22))
      ;;
    3)  # FRONT - 肩前合
      lshoulder_r=$((body_r + 6)); rshoulder_r=$((body_r + 6))
      lshoulder_c=$((body_c + 10)); rshoulder_c=$((body_c + 18))
      ;;
  esac

  # 画肩膀方块
  buf_at "$lshoulder_r"        "$lshoulder_c" "bgreen" "╔══╗"
  buf_at "$((lshoulder_r + 1))" "$lshoulder_c" "bgreen" "║██║"
  buf_at "$((lshoulder_r + 2))" "$lshoulder_c" "bgreen" "╚══╝"
  buf_at "$rshoulder_r"        "$rshoulder_c" "bgreen" "╔══╗"
  buf_at "$((rshoulder_r + 1))" "$rshoulder_c" "bgreen" "║██║"
  buf_at "$((rshoulder_r + 2))" "$rshoulder_c" "bgreen" "╚══╝"

  # 圆周轨迹（虚线圆指示运动方向）
  local circle_r=$((body_r + 6)) circle_c=$((body_c + 13))
  buf_at "$circle_r"        "$circle_c" "byellow" "↻"

  # 当前阶段标签
  local labels=("UP" "BACK" "DOWN" "FRONT")
  local cn_labels=("肩上耸" "肩后展" "肩下沉" "肩前合")
  local dir_arrows=("▲" "◀" "▼" "▶")

  buf_centered "$((CANVAS_BOTTOM - 2))" "byellow" "${dir_arrows[$quadrant]} ${labels[$quadrant]} · ${cn_labels[$quadrant]}"
  buf_centered "$((CANVAS_BOTTOM - 1))" "white" "${DIM}肩部慢慢画圆 ↻  4 拍 = 一圈${RESET}"
}

# ─────────────────────────────────────────────────────
# 动作 6: neck-side 颈侧屈
# 大人形头部偏向左肩 / 右肩
# ─────────────────────────────────────────────────────
render_neck_side() {
  local cc=$(canvas_center_col)
  local cycle=$(( FRAME_IDX % 50 ))
  local side
  if (( cycle < 25 )); then side="left"; else side="right"; fi
  local body_r=$((CANVAS_TOP + 1))
  local body_c=$(( cc - 14 ))

  if [[ "$side" == "left" ]]; then
    # 头向左偏（耳朵贴左肩）
    buf_at "$body_r"          "$body_c" "white"  "         ╭═══════════╮"
    buf_at "$((body_r + 1))"  "$body_c" "white"  "        ╱║  ◕   ◕  ║"
    buf_at "$((body_r + 2))"  "$body_c" "white"  "       ╱ ║    ω    ║"
    buf_at "$((body_r + 3))"  "$body_c" "white"  "      ╱  ╚═══════════╝"
    buf_at "$((body_r + 4))"  "$body_c" "bgreen" "     ╱"
    buf_at "$((body_r + 5))"  "$body_c" "yellow" "  ╔══════╗  ════════════╗"
    buf_at "$((body_r + 6))"  "$body_c" "yellow" "  ║██████║  body         ║"
    buf_at "$((body_r + 7))"  "$body_c" "yellow" "  ╚══════╝  ════════════╝"
    buf_at "$((body_r + 8))"  "$body_c" "white"  "              │"
    buf_at "$((body_r + 9))"  "$body_c" "white"  "              │"
    buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "◀ LEFT · 左耳贴左肩"
  else
    # 头向右偏
    buf_at "$body_r"          "$body_c" "white"  "    ╭═══════════╮"
    buf_at "$((body_r + 1))"  "$body_c" "white"  "    ║  ◕   ◕  ║╲"
    buf_at "$((body_r + 2))"  "$body_c" "white"  "    ║    ω    ║ ╲"
    buf_at "$((body_r + 3))"  "$body_c" "white"  "    ╚═══════════╝  ╲"
    buf_at "$((body_r + 4))"  "$body_c" "bgreen" "                    ╲"
    buf_at "$((body_r + 5))"  "$body_c" "yellow" "  ╔════════════╗  ╔══════╗"
    buf_at "$((body_r + 6))"  "$body_c" "yellow" "  ║   body     ║  ║██████║"
    buf_at "$((body_r + 7))"  "$body_c" "yellow" "  ╚════════════╝  ╚══════╝"
    buf_at "$((body_r + 8))"  "$body_c" "white"  "         │"
    buf_at "$((body_r + 9))"  "$body_c" "white"  "         │"
    buf_centered "$((CANVAS_BOTTOM - 2))" "bgreen" "RIGHT ▶ · 右耳贴右肩"
  fi

  # 剩余倒计时（每边 5 秒，每秒一次 tick）
  local side_elapsed remain
  if [[ "$side" == "left" ]]; then side_elapsed=$cycle; else side_elapsed=$((cycle - 25)); fi
  remain=$(( 5 - side_elapsed / 5 ))
  (( remain < 0 )) && remain=0
  buf_centered "$((CANVAS_BOTTOM - 1))" "bred" "${BOLD}保持 ${remain}s${RESET}"
}

# ─────────────────────────────────────────────────────
# 动作 7: breath-box 方框呼吸
# 大方框 + 沿边移动的光球 + 中央大数字
# 4 阶段：吸-屏-呼-屏，各 4 秒（20 帧）
# ─────────────────────────────────────────────────────
render_breath_box() {
  local cc=$(canvas_center_col)
  local cr=$(canvas_center_row)
  local box_w=42 box_h=11
  local box_c=$(( cc - box_w / 2 ))
  local box_r=$(( CANVAS_TOP + 2 ))

  local cycle=$(( FRAME_IDX % 80 ))
  local phase=$(( cycle / 20 ))
  local prog=$(( cycle % 20 ))
  local phase_names=("INHALE" "HOLD" "EXHALE" "HOLD")
  local phase_cn=("吸 气" "屏 住" "呼 气" "屏 住")
  local phase_colors=("bgreen" "byellow" "bcyan" "bmagenta")
  local pcolor="${phase_colors[$phase]}"

  # 画方框
  local top="╔$(make_line $((box_w - 2)) '═')╗"
  local bot="╚$(make_line $((box_w - 2)) '═')╝"
  buf_at "$box_r" "$box_c" "$pcolor" "$top"
  local r
  for ((r=1; r<box_h-1; r++)); do
    buf_at $((box_r + r)) "$box_c" "$pcolor" "║"
    buf_at $((box_r + r)) $((box_c + box_w - 1)) "$pcolor" "║"
  done
  buf_at $((box_r + box_h - 1)) "$box_c" "$pcolor" "$bot"

  # 沿边的"呼吸光球"位置
  local ball_r ball_c
  case $phase in
    0) ball_r=$box_r;                       ball_c=$(( box_c + 1 + (box_w - 3) * prog / 19 ));;
    1) ball_r=$(( box_r + 1 + (box_h - 3) * prog / 19 )); ball_c=$(( box_c + box_w - 1 ));;
    2) ball_r=$(( box_r + box_h - 1 )); ball_c=$(( box_c + box_w - 2 - (box_w - 3) * prog / 19 ));;
    3) ball_r=$(( box_r + box_h - 2 - (box_h - 3) * prog / 19 )); ball_c=$box_c;;
  esac
  buf_at "$ball_r" "$ball_c" "bred" "●"

  # 阶段名（大字 banner，但 banner 太大要塞中央有点挤，用粗体文字代替）
  local phase_text="${phase_names[$phase]} · ${phase_cn[$phase]}"
  buf_at $((box_r + 3)) "$((box_c + (box_w - ${#phase_text} ) / 2 ))" "$pcolor" "${BOLD}${phase_text}"

  # 大数字倒计时
  local stage_remain=$(( 4 - prog / 5 ))
  (( stage_remain < 1 )) && stage_remain=1

  # 用 banner 字体画数字（5 行 × 5 列）
  local digit_lines; digit_lines=$(banner_lines "$stage_remain")
  local dr=0 dline
  while IFS= read -r dline; do
    buf_at "$((box_r + 5 + dr))" "$((box_c + (box_w - ${#dline}) / 2 ))" "$pcolor" "${BOLD}${dline}"
    dr=$((dr + 1))
  done <<< "$digit_lines"

  # 4 拍指示器（4 个圆点显示当前阶段）
  local dots="" p
  for p in 0 1 2 3; do
    if (( p == phase )); then dots+="●  "; else dots+="○  "; fi
  done
  buf_centered "$((CANVAS_BOTTOM - 1))" "white" "$dots ${DIM}4-4-4-4${RESET}"
}

# ─────────────────────────────────────────────────────
# 分发
# ─────────────────────────────────────────────────────
render_dispatch() {
  local action="$1"
  case "$action" in
    eye-track)     render_eye_track;;
    eye-saccade)   render_eye_saccade;;
    finger-piano)  render_finger_piano;;
    finger-pose)   render_finger_pose;;
    shoulder-roll) render_shoulder_roll;;
    neck-side)     render_neck_side;;
    breath-box)    render_breath_box;;
  esac
}

# ═══════════════════════════════════════════════════════
# 主渲染：BANNER + CANVAS + BIG OCTOPUS + BUDDY + 进度 + 统计
# ═══════════════════════════════════════════════════════
render_screen() {
  local action="$1" action_idx="$2" elapsed="$3" duration="$4" color="$5"

  refresh_term_size
  local cols=$CACHED_COLS
  local lines=$CACHED_LINES

  # 动态画布尺寸：保留右侧 35 列给大章鱼 + buddy
  if (( cols >= 120 )); then
    CANVAS_RIGHT=$(( cols - 36 ))
  elif (( cols >= 90 )); then
    CANVAS_RIGHT=$(( cols - 30 ))
  else
    CANVAS_RIGHT=$(( cols - 2 ))
  fi
  CANVAS_TOP=11
  CANVAS_BOTTOM=$(( lines - 5 ))

  local title; title=$(action_title_for "$action")
  local hint;  hint=$(action_hint_for "$action")
  local banner_text="${ACTION_BANNERS[$action_idx]}"
  local remain=$(( duration - elapsed ))
  (( remain < 0 )) && remain=0

  buf_reset

  # ── 顶部 header 行 ──
  buf_clear_rows 1 2
  local header_text=" Claude Coach · $((action_idx + 1))/${#ACTIONS[@]} · ${title} · ${hint} "
  buf_at 1 1 "$color" "${BOLD}${header_text}"
  buf_at 2 1 "$color" "$(make_line "$cols" '═')"

  # ── 大字 banner（rows 4-8，5 行） ──
  buf_clear_rows 3 9
  # banner 居中（但 banner 是基于 CACHED_COLS 居中，可能跟 canvas 不对齐；先用 CACHED_COLS 居中）
  buf_banner_centered 4 "$color" "$banner_text"

  # ── 主 canvas 区 ──
  buf_clear_rows 10 "$((lines - 5))"
  render_dispatch "$action"

  # ── 右侧：大章鱼 + buddy + 气泡 ──
  if (( cols >= 90 && lines >= 28 )); then
    # 大章鱼：右侧上方，11 字符行
    local oct_col=$(( cols - 32 ))
    local oct_row=10
    draw_big_octopus "$(eye_track_pose_for_octopus "$action")" "$oct_row" "$oct_col"

    # buddy + 气泡：右下方
    local buddy_row=$(( lines - 9 ))
    local buddy_col=$(( cols - 30 ))
    draw_buddy_with_bubble "$buddy_row" "$buddy_col" "$action" "$FRAME_IDX" "bcyan"
  fi

  # ── 大数字倒计时（左下） ──
  if (( cols >= 60 )); then
    local big_row=$(( lines - 9 ))
    local big_col=2
    buf_at "$big_row" "$big_col" "byellow" "${BOLD}剩余"
    local d_lines; d_lines=$(banner_lines "$remain")
    local dr=0 dline
    while IFS= read -r dline; do
      buf_at "$((big_row + 1 + dr))" "$big_col" "byellow" "$dline"
      dr=$((dr + 1))
    done <<< "$d_lines"
    buf_at "$((big_row + 7))" "$big_col" "yellow" "  秒"
  fi

  # ── 底部 progress bar + stats ──
  buf_clear_rows "$((lines - 2))" "$lines"
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
  buf_at "$lines" 2 "" "${DIM}总累计${RESET} $(format_duration "$total_ms")   ${DIM}今日${RESET} $(format_duration "$today_ms")   ${DIM}本次${RESET} $(format_duration "$session_ms")   ${DIM}✻ Claude Coach · ${BUDDY_NAME}${RESET}"

  buf_flush
}

# 决定大章鱼的眼神 pose（跟随当前动作上下文）
# eye-track 时跟随当前方向；其他动作 idle 切换
eye_track_pose_for_octopus() {
  local action="$1"
  if [[ "$action" == "eye-track" ]]; then
    local pos_idx=$(( (FRAME_IDX / 10) % ${#EYE_TRACK_SEQUENCE[@]} ))
    echo "${EYE_TRACK_SEQUENCE[$pos_idx]}"
    return
  fi
  # 其他动作 idle 模式：每 ~4s 切个 pose
  local idle_poses=(center center blink center left center right center)
  local p=$(( (FRAME_IDX / 20) % ${#idle_poses[@]} ))
  echo "${idle_poses[$p]}"
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
  local reason="${1:-signal}"
  local now=$SECONDS
  ACCUMULATED=$now
  flush_stats "$now"
  cw_log "animation cleanup reason=$reason elapsed=${now}s"
  printf '%s%s' "$ALT_SCREEN_OFF" "$SHOW_CURSOR"
  printf '\n\n        '
  printf '%s╭──────────────────────╮\n' "$(color_code cyan)"
  printf '        │   %s✻ 辛苦了，做得真棒%s%s   │\n' "$(color_code yellow)" "$RESET" "$(color_code cyan)"
  printf '        ╰──────────────────────╯%s\n\n' "$RESET"
  printf '        本次运动 %s%d%s 秒\n' "${BOLD}$(color_code yellow)" "$now" "$RESET"
  sleep 0.3
  exit 0
}
trap 'cleanup signal' TERM INT HUP

self_check() {
  if [[ -n "$RUNTIME_FILE" && ! -f "$RUNTIME_FILE" ]]; then
    cleanup "runtime-gone"
  fi
  if [[ -n "$CLAUDE_PID" && "$CLAUDE_PID" != "0" ]]; then
    if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
      cleanup "claude-dead"
    fi
  fi
}

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

      if (( FRAME_IDX % SELF_CHECK_INTERVAL == 0 )); then
        self_check
      fi
    done

    ai_raw=$((ai_raw + 1))
    FRAME_IDX=0
  done
done
