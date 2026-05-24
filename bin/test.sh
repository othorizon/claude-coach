#!/usr/bin/env bash
# claude-coach 动画手动测试脚本
# 用法:
#   ./bin/test.sh                  # 随机起点跑完整循环
#   ./bin/test.sh shoulder-roll    # 从指定动作开始
#   ./bin/test.sh -h               # 显示帮助
#
# Ctrl-C 退出。所有数据写到 /tmp/cw-test-data-$$，不影响主 stats.json。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
用法: $0 [action-name]

可用动作：
  eye-track       眼神追踪
  eye-saccade     跳视训练（四方向）
  finger-piano    手指钢琴
  finger-pose     手势造型
  shoulder-roll   肩部画圆
  neck-side       颈侧屈伸
  breath-box      方框呼吸

不传则随机起点，按顺序循环所有动作。Ctrl-C 退出。
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

ACTION="${1:-}"
SESSION="test-$$"

# 隔离测试数据
export CLAUDE_PLUGIN_DATA="/tmp/cw-test-data-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"

RUNTIME="$CLAUDE_PLUGIN_DATA/runtime-${SESSION}.json"
cat > "$RUNTIME" <<EOF
{
  "session_id": "$SESSION",
  "session_ms": 0,
  "started_at": $(date +%s)
}
EOF

cleanup() {
  rm -rf "$CLAUDE_PLUGIN_DATA"
}
trap cleanup EXIT

export CW_TEST_ACTION="$ACTION"

# claude_pid 传 $$（当前 shell），自检不会把动画杀掉
"$SCRIPT_DIR/animation.sh" "$SESSION" "$RUNTIME" "$$"
