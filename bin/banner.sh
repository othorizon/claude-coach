#!/usr/bin/env bash
# claude-coach banner.sh
# 5 行 × 5 列 block 字体（A-Z + 0-9 + 空格 + 冒号）
# 输出函数：banner_lines "TEXT" → 通过 echo 给出 5 行

# 每个字符 5 行 × 5 列。用 █ 实心方块字符。
# bash 3.2 兼容：纯 case，无关联数组。

banner_glyph_row() {
  local c="$1" r="$2"
  case "$c:$r" in
    "A:0") echo " ███ ";; "A:1") echo "█   █";; "A:2") echo "█████";; "A:3") echo "█   █";; "A:4") echo "█   █";;
    "B:0") echo "████ ";; "B:1") echo "█   █";; "B:2") echo "████ ";; "B:3") echo "█   █";; "B:4") echo "████ ";;
    "C:0") echo " ████";; "C:1") echo "█    ";; "C:2") echo "█    ";; "C:3") echo "█    ";; "C:4") echo " ████";;
    "D:0") echo "████ ";; "D:1") echo "█   █";; "D:2") echo "█   █";; "D:3") echo "█   █";; "D:4") echo "████ ";;
    "E:0") echo "█████";; "E:1") echo "█    ";; "E:2") echo "████ ";; "E:3") echo "█    ";; "E:4") echo "█████";;
    "F:0") echo "█████";; "F:1") echo "█    ";; "F:2") echo "████ ";; "F:3") echo "█    ";; "F:4") echo "█    ";;
    "G:0") echo " ████";; "G:1") echo "█    ";; "G:2") echo "█  ██";; "G:3") echo "█   █";; "G:4") echo " ████";;
    "H:0") echo "█   █";; "H:1") echo "█   █";; "H:2") echo "█████";; "H:3") echo "█   █";; "H:4") echo "█   █";;
    "I:0") echo "█████";; "I:1") echo "  █  ";; "I:2") echo "  █  ";; "I:3") echo "  █  ";; "I:4") echo "█████";;
    "J:0") echo "█████";; "J:1") echo "   █ ";; "J:2") echo "   █ ";; "J:3") echo "█  █ ";; "J:4") echo " ██  ";;
    "K:0") echo "█   █";; "K:1") echo "█  █ ";; "K:2") echo "███  ";; "K:3") echo "█  █ ";; "K:4") echo "█   █";;
    "L:0") echo "█    ";; "L:1") echo "█    ";; "L:2") echo "█    ";; "L:3") echo "█    ";; "L:4") echo "█████";;
    "M:0") echo "█   █";; "M:1") echo "██ ██";; "M:2") echo "█ █ █";; "M:3") echo "█   █";; "M:4") echo "█   █";;
    "N:0") echo "█   █";; "N:1") echo "██  █";; "N:2") echo "█ █ █";; "N:3") echo "█  ██";; "N:4") echo "█   █";;
    "O:0") echo " ███ ";; "O:1") echo "█   █";; "O:2") echo "█   █";; "O:3") echo "█   █";; "O:4") echo " ███ ";;
    "P:0") echo "████ ";; "P:1") echo "█   █";; "P:2") echo "████ ";; "P:3") echo "█    ";; "P:4") echo "█    ";;
    "Q:0") echo " ███ ";; "Q:1") echo "█   █";; "Q:2") echo "█   █";; "Q:3") echo "█  █ ";; "Q:4") echo " ██ █";;
    "R:0") echo "████ ";; "R:1") echo "█   █";; "R:2") echo "████ ";; "R:3") echo "█  █ ";; "R:4") echo "█   █";;
    "S:0") echo " ████";; "S:1") echo "█    ";; "S:2") echo " ███ ";; "S:3") echo "    █";; "S:4") echo "████ ";;
    "T:0") echo "█████";; "T:1") echo "  █  ";; "T:2") echo "  █  ";; "T:3") echo "  █  ";; "T:4") echo "  █  ";;
    "U:0") echo "█   █";; "U:1") echo "█   █";; "U:2") echo "█   █";; "U:3") echo "█   █";; "U:4") echo " ███ ";;
    "V:0") echo "█   █";; "V:1") echo "█   █";; "V:2") echo "█   █";; "V:3") echo " █ █ ";; "V:4") echo "  █  ";;
    "W:0") echo "█   █";; "W:1") echo "█   █";; "W:2") echo "█ █ █";; "W:3") echo "██ ██";; "W:4") echo "█   █";;
    "X:0") echo "█   █";; "X:1") echo " █ █ ";; "X:2") echo "  █  ";; "X:3") echo " █ █ ";; "X:4") echo "█   █";;
    "Y:0") echo "█   █";; "Y:1") echo " █ █ ";; "Y:2") echo "  █  ";; "Y:3") echo "  █  ";; "Y:4") echo "  █  ";;
    "Z:0") echo "█████";; "Z:1") echo "   █ ";; "Z:2") echo "  █  ";; "Z:3") echo " █   ";; "Z:4") echo "█████";;
    "0:0") echo " ███ ";; "0:1") echo "█  ██";; "0:2") echo "█ █ █";; "0:3") echo "██  █";; "0:4") echo " ███ ";;
    "1:0") echo "  █  ";; "1:1") echo " ██  ";; "1:2") echo "  █  ";; "1:3") echo "  █  ";; "1:4") echo " ███ ";;
    "2:0") echo " ███ ";; "2:1") echo "█   █";; "2:2") echo "   █ ";; "2:3") echo " █   ";; "2:4") echo "█████";;
    "3:0") echo " ███ ";; "3:1") echo "█   █";; "3:2") echo "  ██ ";; "3:3") echo "█   █";; "3:4") echo " ███ ";;
    "4:0") echo "█   █";; "4:1") echo "█   █";; "4:2") echo "█████";; "4:3") echo "    █";; "4:4") echo "    █";;
    "5:0") echo "█████";; "5:1") echo "█    ";; "5:2") echo "████ ";; "5:3") echo "    █";; "5:4") echo "████ ";;
    "6:0") echo " ████";; "6:1") echo "█    ";; "6:2") echo "████ ";; "6:3") echo "█   █";; "6:4") echo " ███ ";;
    "7:0") echo "█████";; "7:1") echo "    █";; "7:2") echo "   █ ";; "7:3") echo "  █  ";; "7:4") echo "  █  ";;
    "8:0") echo " ███ ";; "8:1") echo "█   █";; "8:2") echo " ███ ";; "8:3") echo "█   █";; "8:4") echo " ███ ";;
    "9:0") echo " ███ ";; "9:1") echo "█   █";; "9:2") echo " ████";; "9:3") echo "    █";; "9:4") echo "████ ";;
    " :0") echo "     ";; " :1") echo "     ";; " :2") echo "     ";; " :3") echo "     ";; " :4") echo "     ";;
    "::0") echo "     ";; "::1") echo "  █  ";; "::2") echo "     ";; "::3") echo "  █  ";; "::4") echo "     ";;
    "!:0") echo "  █  ";; "!:1") echo "  █  ";; "!:2") echo "  █  ";; "!:3") echo "     ";; "!:4") echo "  █  ";;
    "-:0") echo "     ";; "-:1") echo "     ";; "-:2") echo "█████";; "-:3") echo "     ";; "-:4") echo "     ";;
    *) printf '%-5s' " ";;
  esac
}

# 渲染整段大字 banner，返回 5 行（每行各字母之间 1 空格分隔）
# 用法：banner_lines "EYE TRACK"
banner_lines() {
  local s="$1" r line c i ch
  for r in 0 1 2 3 4; do
    line=""
    for ((i=0; i<${#s}; i++)); do
      ch="${s:$i:1}"
      # 转大写
      case "$ch" in
        [a-z]) ch=$(printf '%s' "$ch" | tr '[:lower:]' '[:upper:]');;
      esac
      line+="$(banner_glyph_row "$ch" "$r") "
    done
    echo "$line"
  done
}

# 把 banner 写入 FRAME_BUF（需要 animation.sh 的 buf_at + CACHED_COLS）
buf_banner_centered() {
  local row="$1" color="$2" text="$3"
  # 计算总宽度：每字符 5 col + 1 空格
  local width=$(( ${#text} * 6 ))
  local col=$(( (CACHED_COLS - width) / 2 + 1 ))
  (( col < 1 )) && col=1
  local r=0 line
  while IFS= read -r line; do
    buf_at "$((row + r))" "$col" "$color" "$line"
    r=$((r + 1))
  done < <(banner_lines "$text")
}
