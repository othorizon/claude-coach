#!/usr/bin/env bash
# claude-coach octopus_big.sh
# 大彩色章鱼：28 像素宽 × 22 像素高（每行 28 字符，每两行像素 = 1 字符行用半块 ▀ 渲染）
# 6 种 pose（center/up/down/left/right/blink），仅眼珠位置变化。

# 颜色定义（在 animation.sh 的 build_sprite_row 已经识别，这里复用并扩展）
# O = 深粉轮廓     (140;40;70)
# P = 粉色主体     (240;130;160)
# p = 粉色阴影     (200;90;120)
# R = 粉色高光     (255;200;220)
# W = 白色眼眶     (250;245;250)
# E = 深色眼珠     (25;20;40)
# h = 眼珠高光     (255;255;255)
# m = 嘴巴深色     (130;30;60)
# M = 嘴唇         (210;70;110)
# e = 闭眼睫毛     (100;40;70)

# 大章鱼颜色映射函数（由 animation.sh 的 sprite_color_for 调用补充）
big_octopus_color_for() {
  case "$1" in
    O) echo "140;40;70" ;;
    P) echo "240;130;160" ;;
    p) echo "200;90;120" ;;
    R) echo "255;200;220" ;;
    W) echo "250;245;250" ;;
    E) echo "25;20;40" ;;
    h) echo "255;255;255" ;;
    m) echo "130;30;60" ;;
    M) echo "210;70;110" ;;
    e) echo "100;40;70" ;;
    *) echo "" ;;
  esac
}

# 大章鱼底版（28 列 × 22 行像素，11 字符行）。眼珠位置用占位符标记：
#   {LU} {LM} {LL}  左眼上中下行的中段
#   {LL} {LM} {LR}  左眼三列（左中右）
# 实际生成时按 pose 替换。
# 我们用更简单的方式：base 里把眼眶整块写好，pose 函数只替换中心眼珠像素。
#
# 眼眶位置：
#   左眼：行 7-9，列 6-10（5 宽 × 3 高，中心 col=8, row=8）
#   右眼：行 7-9，列 17-21（5 宽 × 3 高，中心 col=19, row=8）

# Base：用 "L" 和 "R" 占位代替眼眶中心（之后被 pose 替换为 E/W/e 等）
# 22 行 × 28 列
__BIG_OCTOPUS_BASE='............................
.........OOOOOOOOOO.........
.......OOPPPPPPPPPPPP.......
......OPPRRRPPPPPPPPPpO.....
.....OPRRRRRRPPPPPPPPPpO....
....OPRRRRRRRPPPPPPPPPPpO...
....OPRRRRRRRPPPPPPPPPPPpO..
....OPRRRWWWWWPPPWWWWWRPpO..
....OPPRRW---WPPPW---WRPpO..
....OPRRRWWWWWPPPWWWWWRPpO..
....OPRRRRRRRRRRRRRRRRRPpO..
....OPRRRRRRRRRRRRRRRRRPpO..
....OPPRRRRR.MMMmMM.RRRPpO..
.....OPPRRR.MMmmmMM.RRPpO...
.....OOPPRRR.MMMMM.RRPPpO...
......OOPPRRRRR.RRRRRPPpO...
........OOPPPPPPPPPPPPpO....
..........OOOPPPPPPPpOO.....
............................
......OO.OOO.OO.OOO.OO......
.....OO.OO.OOO.OO.OOO.OO....
....OO.OO.OO.OOO.OO.OOO.OO..'

# pose 替换：把 "---" 替换成眼珠图案
# 三个字符表示眼眶中段 3 像素：
#   center  → " E "
#   up      → " E "  但同时把眼眶上方第一行加上 E（这个由完整模板支持）
# 简化方案：眼眶 5 宽 × 3 高，眼珠 1 像素，可在 5×3 中的任意位置
# 我们用 PRE/MID/POST 三层替换：
__big_octopus_replace_eye() {
  local txt="$1" pose="$2"
  # pose 指定左右眼中段位置 (上行、中行、下行的 5 字符内容)
  local upper middle lower
  case "$pose" in
    center) upper="WWWWW"; middle="WWEWW"; lower="WWWWW" ;;
    up)     upper="WWEWW"; middle="WWWWW"; lower="WWWWW" ;;
    down)   upper="WWWWW"; middle="WWWWW"; lower="WWEWW" ;;
    left)   upper="WWWWW"; middle="WEWWW"; lower="WWWWW" ;;
    right)  upper="WWWWW"; middle="WWWEW"; lower="WWWWW" ;;
    blink)  upper="WWWWW"; middle="eeeee"; lower="WWWWW" ;;
    *)      upper="WWWWW"; middle="WWEWW"; lower="WWWWW" ;;
  esac

  # base 里有两块 WWWWW...WWWWW，我们逐行替换上中下三行
  # 行 7 (上眼眶行)、行 8 (中)、行 9 (下) → 0-indexed
  # 通过逐行处理
  local IFS=$'\n'
  local lines=($txt)
  unset IFS
  local i out=""
  for ((i=0; i<${#lines[@]}; i++)); do
    case $i in
      7)  # 上眼眶行：把两块 WWWWW 替换成 upper
        out+="${lines[$i]//WWWWW/$upper}"$'\n'
        ;;
      8)  # 中眼眶行：把两块 W---W 替换成 middle
        out+="${lines[$i]//W---W/$middle}"$'\n'
        ;;
      9)  # 下眼眶行
        out+="${lines[$i]//WWWWW/$lower}"$'\n'
        ;;
      *)
        out+="${lines[$i]}"$'\n'
        ;;
    esac
  done
  printf '%s' "$out"
}

# 获取某 pose 的完整像素数据
big_octopus_pose_data() {
  __big_octopus_replace_eye "$__BIG_OCTOPUS_BASE" "$1"
}

# 渲染：在 (base_row, base_col) 画大章鱼到 FRAME_BUF
# 依赖 animation.sh 的 build_sprite_row 和 FRAME_BUF / buf_at
# 因为颜色映射可能在 animation.sh 主表中找不到 R/W/E 等，
# 这里临时改写 sprite_color_for 太复杂；我们直接调用 big_octopus_build_row
big_octopus_build_row() {
  local upper="$1" lower="$2"
  local w=${#upper}
  local out=""
  local c uc lc ucol lcol
  for ((c=0; c<w; c++)); do
    uc="${upper:$c:1}"
    lc="${lower:$c:1}"
    ucol=$(big_octopus_color_for "$uc")
    lcol=$(big_octopus_color_for "$lc")
    if [[ -z "$ucol" && -z "$lcol" ]]; then
      out+=" "
    elif [[ -z "$lcol" ]]; then
      out+=$'\033'"[38;2;${ucol}m"$'\033'"[49m▀"
    elif [[ -z "$ucol" ]]; then
      out+=$'\033'"[39m"$'\033'"[48;2;${lcol}m▀"
    else
      out+=$'\033'"[38;2;${ucol}m"$'\033'"[48;2;${lcol}m▀"
    fi
  done
  out+=$'\033'"[0m"
  printf '%s' "$out"
}

draw_big_octopus() {
  local pose="$1" base_row="$2" base_col="$3"
  local data; data=$(big_octopus_pose_data "$pose")

  local IFS=$'\n'
  local rows=($data)
  unset IFS

  local i char_row=0 upper lower row pos
  for ((i=0; i<${#rows[@]}; i+=2)); do
    upper="${rows[$i]}"
    lower="${rows[$((i+1))]:-............................}"
    row=$(big_octopus_build_row "$upper" "$lower")
    printf -v pos '%s[%d;%dH' $'\033' "$((base_row + char_row))" "$base_col"
    FRAME_BUF+="$pos$row"
    char_row=$((char_row + 1))
  done
}
