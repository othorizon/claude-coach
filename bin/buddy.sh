#!/usr/bin/env bash
# claude-coach buddy.sh
# 移植自 Claude Code src/buddy/sprites.ts 的 buddy 角色精灵表。
# 每个角色 5 行 × 12 字符；3 帧待机动画；{E} 占位符替换成眼睛字符。
# bash 3.2 兼容（不依赖 \u 转义）。

BUDDY_SPECIES=(cat capybara robot octopus dragon)

# 眼睛字符候选（来自 Claude Code 内置）
BUDDY_EYES=('·' '✦' '◉' '°')

# Sprite 数据存储为 SPRITE_<species>_<frame>_lineN
# 启动时一次性初始化

__init_buddy_sprites() {
  # ─────────── cat ───────────
  SPRITE_cat_0_line0='            '
  SPRITE_cat_0_line1='   /\_/\    '
  SPRITE_cat_0_line2='  ( {E}   {E})  '
  SPRITE_cat_0_line3='  (  ω  )   '
  SPRITE_cat_0_line4='  (")_(")   '

  SPRITE_cat_1_line0='            '
  SPRITE_cat_1_line1='   /\_/\    '
  SPRITE_cat_1_line2='  ( {E}   {E})  '
  SPRITE_cat_1_line3='  (  ω  )   '
  SPRITE_cat_1_line4='  (")_(")~  '

  SPRITE_cat_2_line0='            '
  SPRITE_cat_2_line1='   /\-/\    '
  SPRITE_cat_2_line2='  ( {E}   {E})  '
  SPRITE_cat_2_line3='  (  ω  )   '
  SPRITE_cat_2_line4='  (")_(")   '

  # ─────────── capybara ───────────
  SPRITE_capybara_0_line0='            '
  SPRITE_capybara_0_line1='  n______n  '
  SPRITE_capybara_0_line2=' ( {E}    {E} ) '
  SPRITE_capybara_0_line3=' (   oo   ) '
  SPRITE_capybara_0_line4='  `------´  '

  SPRITE_capybara_1_line0='            '
  SPRITE_capybara_1_line1='  n______n  '
  SPRITE_capybara_1_line2=' ( {E}    {E} ) '
  SPRITE_capybara_1_line3=' (   Oo   ) '
  SPRITE_capybara_1_line4='  `------´  '

  SPRITE_capybara_2_line0='    ~  ~    '
  SPRITE_capybara_2_line1='  u______n  '
  SPRITE_capybara_2_line2=' ( {E}    {E} ) '
  SPRITE_capybara_2_line3=' (   oo   ) '
  SPRITE_capybara_2_line4='  `------´  '

  # ─────────── robot ───────────
  SPRITE_robot_0_line0='            '
  SPRITE_robot_0_line1='   .[||].   '
  SPRITE_robot_0_line2='  [ {E}  {E} ]  '
  SPRITE_robot_0_line3='  [ ==== ]  '
  SPRITE_robot_0_line4='  `------´  '

  SPRITE_robot_1_line0='            '
  SPRITE_robot_1_line1='   .[||].   '
  SPRITE_robot_1_line2='  [ {E}  {E} ]  '
  SPRITE_robot_1_line3='  [ -==- ]  '
  SPRITE_robot_1_line4='  `------´  '

  SPRITE_robot_2_line0='     *      '
  SPRITE_robot_2_line1='   .[||].   '
  SPRITE_robot_2_line2='  [ {E}  {E} ]  '
  SPRITE_robot_2_line3='  [ ==== ]  '
  SPRITE_robot_2_line4='  `------´  '

  # ─────────── octopus（小） ───────────
  SPRITE_octopus_0_line0='            '
  SPRITE_octopus_0_line1='   .----.   '
  SPRITE_octopus_0_line2='  ( {E}  {E} )  '
  SPRITE_octopus_0_line3='  (______)  '
  SPRITE_octopus_0_line4='  /\/\/\/\  '

  SPRITE_octopus_1_line0='            '
  SPRITE_octopus_1_line1='   .----.   '
  SPRITE_octopus_1_line2='  ( {E}  {E} )  '
  SPRITE_octopus_1_line3='  (______)  '
  SPRITE_octopus_1_line4='  \/\/\/\/  '

  SPRITE_octopus_2_line0='     o      '
  SPRITE_octopus_2_line1='   .----.   '
  SPRITE_octopus_2_line2='  ( {E}  {E} )  '
  SPRITE_octopus_2_line3='  (______)  '
  SPRITE_octopus_2_line4='  /\/\/\/\  '

  # ─────────── dragon ───────────
  SPRITE_dragon_0_line0='            '
  SPRITE_dragon_0_line1='  /^\  /^\  '
  SPRITE_dragon_0_line2=' <  {E}  {E}  > '
  SPRITE_dragon_0_line3=' (   ~~   ) '
  SPRITE_dragon_0_line4='  `-vvvv-´  '

  SPRITE_dragon_1_line0='            '
  SPRITE_dragon_1_line1='  /^\  /^\  '
  SPRITE_dragon_1_line2=' <  {E}  {E}  > '
  SPRITE_dragon_1_line3=' (        ) '
  SPRITE_dragon_1_line4='  `-vvvv-´  '

  SPRITE_dragon_2_line0='   ~    ~   '
  SPRITE_dragon_2_line1='  /^\  /^\  '
  SPRITE_dragon_2_line2=' <  {E}  {E}  > '
  SPRITE_dragon_2_line3=' (   ~~   ) '
  SPRITE_dragon_2_line4='  `-vvvv-´  '
}
__init_buddy_sprites

# 取某物种某帧某行原始字符串（{E} 未替换）
buddy_raw_line() {
  local sp="$1" fr="$2" ln="$3"
  local var="SPRITE_${sp}_${fr}_line${ln}"
  printf '%s' "${!var-}"
}

# 取某物种某帧某行（{E} 已替换）
buddy_line() {
  local sp="$1" fr="$2" ln="$3" eye="$4"
  local raw; raw=$(buddy_raw_line "$sp" "$fr" "$ln")
  printf '%s' "${raw//\{E\}/$eye}"
}

# 物种角色名（中文叫法）
buddy_chinese_name() {
  case "$1" in
    cat)      echo "猫教练";;
    capybara) echo "水豚教练";;
    robot)    echo "机器人教练";;
    octopus)  echo "小章鱼教练";;
    dragon)   echo "龙教练";;
    *)        echo "$1";;
  esac
}

# 用 session_id 字符串 hash 决定本会话的 buddy 角色（每会话固定）
buddy_for_session() {
  local sid="${1:-default}"
  local n=${#BUDDY_SPECIES[@]}
  local h=0 i ch ord
  for ((i=0; i<${#sid}; i++)); do
    ch="${sid:$i:1}"
    printf -v ord '%d' "'$ch"
    h=$(( (h * 31 + ord) & 0x7fffffff ))
  done
  echo "${BUDDY_SPECIES[$((h % n))]}"
}

# 同理给 eye 选个稳定值
buddy_eye_for_session() {
  local sid="${1:-default}"
  local n=${#BUDDY_EYES[@]}
  local h=0 i ch ord
  for ((i=0; i<${#sid}; i++)); do
    ch="${sid:$i:1}"
    printf -v ord '%d' "'$ch"
    h=$(( (h * 37 + ord + 7) & 0x7fffffff ))
  done
  echo "${BUDDY_EYES[$((h % n))]}"
}

# 把 buddy 画到 (base_row, base_col)，写入 FRAME_BUF
# 调用方需要先 source animation.sh 里的 buf_at
draw_buddy_at() {
  local sp="$1" fr="$2" eye="$3" base_row="$4" base_col="$5" color="$6"
  local i line
  for i in 0 1 2 3 4; do
    line=$(buddy_line "$sp" "$fr" "$i" "$eye")
    [[ -z "$line" ]] && continue
    buf_at "$((base_row + i))" "$base_col" "$color" "$line"
  done
}
