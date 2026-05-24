# claude-coach

> Claude Code 干活时弹一个动画引导你做眼保健操和健康小动作的插件。

Claude Code 在跑长任务时，与其干等到颈椎抗议，不如顺手做点眼保健操、活动一下手腕肩膀脖子。这个插件就是干这个的：

- Claude 真正在工作时（处理 prompt、调用工具），自动弹出一个动画区域，跟着 Claude 教练（✻ 角色 + 实时台词）做 8 组循环动作。
- 动画用大画面 + 彩色 ANSI + 大数字倒计时，让你不用凑近也能看清。
- Claude 需要你输入或确认权限时，动画**立刻关闭**让位。
- Claude 又开始工作时，重新弹出。
- 会话结束彻底关闭。
- 累计统计你每天/每周一共"被迫"运动了多少时间。

## 8 个动作（4 分 32 秒一轮，循环）

| 类别 | 动作 | 时长 | 怎么做 |
|---|---|---|---|
| 眼动 | **平滑追踪** | 60s | 两个小人抛球，眼睛跟球往返，头不动 |
| 眼动 | **跳视** | 20s | 两个目标点交替亮起，眼球在两点间快速切换 |
| 眼动 | **远近调焦** | 20s | 屏幕中央小点 ↔ 远方大景，每 3 秒切换聚焦 |
| 手部 | **手指钢琴** | 40s | 拇指依次对捏食 / 中 / 无名 / 小指 |
| 手部 | **手势造型** | 30s | 拳 / 掌 / V / OK / L 五种造型轮换 |
| 上身 | **肩部画圆** | 30s | 肩膀沿上 → 后 → 下 → 前画完整圆周 |
| 上身 | **颈侧屈** | 40s | 头部偏向左肩 / 右肩各保持 5 秒 |
| 呼吸 | **方框呼吸** | 32s | 4-4-4-4 节拍：吸气 - 屏住 - 呼气 - 屏住 |

每个动作都遵循真实的运动节奏（不是为了让你看着 cool 而瞎闪）。眼动训练基于 vision therapy 中的 saccade / smooth pursuit / accommodation；颈肩动作借鉴办公族 ergonomic 例行公事；方框呼吸是 navy SEAL 常用的减压呼吸法。

---

## 两种显示模式

| 模式 | 触发条件 | 行为 |
|---|---|---|
| **tmux 分屏** | 你在 tmux 内启动 Claude Code | `tmux split-window` 切一块占屏 70% 的 pane 跑动画。pane 关掉就消失，不抢窗口焦点。 |
| **popup 新窗口** | 不在 tmux 内（或显式配置） | macOS 下用 `osascript` 弹出 Terminal/iTerm2 新窗口跑动画。窗口浮在前方，关闭时自动关掉。 |

默认是 `auto`：检测到 `$TMUX` 就用 tmux，否则用 popup。

---

## 安装

### 方式 A：本地开发模式

```bash
claude --plugin-dir /path/to/claude-coach
```

适合自己用或调试。每次启动 Claude Code 时带上 `--plugin-dir`。

### 方式 B：通过 marketplace 安装

如果发布到了某个 plugin marketplace：

```bash
# 在 Claude Code 内
/plugin marketplace add <repo>
/plugin install claude-coach
```

---

## 配置

启用插件时 Claude Code 会引导你配置以下选项（也可以后续在 settings.json 里改）：

| 键 | 默认 | 说明 |
|---|---|---|
| `display_mode` | `auto` | `auto` / `tmux` / `popup` |
| `tmux_size_percent` | `70` | tmux 分屏时动画窗占比 (20–90) |
| `tmux_split_direction` | `h` | `h` 右侧竖分屏 / `v` 底部横分屏 |
| `popup_command` | （空）| popup 模式自定义启动命令。留空走平台默认。命令里用 `{script}` 占位真实脚本路径 |

配置存在哪里：`~/.claude/settings.json` → `pluginConfigs["claude-coach..."]options.<key>`。

### 用环境变量临时覆盖

不想动 settings.json，可以在启动 Claude 前导出环境变量（脚本会优先读 env）：

```bash
export CLAUDE_COACH_DISPLAY_MODE=tmux
export CLAUDE_COACH_TMUX_SIZE_PERCENT=50
export CLAUDE_COACH_TMUX_SPLIT_DIRECTION=v
claude
```

### Linux popup 模式

插件会按顺序尝试 `alacritty`、`kitty`、`wezterm`、`gnome-terminal`、`konsole`、`xterm`。如果你的终端不在这里，请用 `popup_command` 显式指定，例如：

```json
"popup_command": "/usr/bin/alacritty -e bash -c {script}"
```

---

## 查看运动统计

在 Claude Code 里输入：

```
/claude-coach:stats
```

会输出类似：

```
🌿 claude-coach · 你的健康账本
──────────────────────────────────
累计运动  4h 18m 10s
今日      12m 34s
本会话    3m 50s

最近 7 天：
  05-18  ███░░░░░░░░░░░░░░░░░  4m
  05-19  ██████████░░░░░░░░░░  12m
  05-20  ████████████████░░░░  18m
  05-21  ░░░░░░░░░░░░░░░░░░░░  ·
  05-22  ███████░░░░░░░░░░░░░  8m
  05-23  ████████████████████  22m
  05-24  ██████████░░░░░░░░░░  12m

💪 坚持下去，颈椎肩膀会感谢你。
```

数据文件在 `~/.claude/plugins/data/claude-coach/stats.json`，想清零直接删掉它。

---

## 工作原理

通过 6 个 Claude Code hook 协调一个长命的动画进程：

```
Claude Code 事件                  动画进程
─────────────────                ──────────
SessionStart    ──→ sweep 孤儿
UserPromptSubmit ──┐
PreToolUse       ──┴→ open  ──→  在 tmux pane / popup 窗口里跑 animation.sh
Notification    ──┐                  ↓
Stop            ──┼→ close ──→  SIGTERM → 累计入 stats.json → 退出
SessionEnd      ──┘
```

正确性关键点（开发参考）：

- `runtime-${session_id}.json` 隔离每个会话的窗口状态，多个并发 Claude 会话不会互相干扰。
- 幂等 `open`：基于 `kill -0` + `ps -o lstart=` 防 PID 复用；不重复开窗。
- 孤儿清理：`SessionStart sweep` 扫描所有 runtime 文件，按 `claude_pid` 已死判定孤儿，用于 Ctrl+C / 崩溃后的清理。
- 非交互模式安全：检测 `CLAUDE_NON_INTERACTIVE` / `CI` 环境变量，CI 场景下静默退出不弹窗。
- 状态文件原子写：临时文件 + `mv`；锁用 `mkdir` 自旋（macOS 没有 `flock(1)`）。
- bash 3.2 兼容（macOS 默认）：不使用 `declare -A` 关联数组。

---

## 文件目录

```
claude-coach/
├── .claude-plugin/plugin.json     manifest + userConfig 声明
├── hooks/hooks.json               6 个事件 → open/close
├── bin/
│   ├── open.sh                    幂等开启窗口
│   ├── close.sh                   同步关闭并 wait
│   ├── animation.sh               长命动画进程
│   ├── render-stats.sh            统计面板渲染
│   └── lib.sh                     公共：原子锁、liveness、配置读取
└── skills/stats/SKILL.md          /claude-coach:stats 触发器

动画完全程序化，无外部帧文件——每个动作一个 render_* 函数，按真实节奏（0.2s 帧间隔）画下一帧。
```

---

## 故障排查

**没看到动画弹出？**

- 检查是不是非交互模式（`-p`、CI）——这种情况下插件主动静默。
- 看日志 `tail -f ~/.claude/plugins/data/claude-coach/debug.log`（hook 触发会有记录）。
- 确认装了 `jq`：`brew install jq` / `apt install jq`。
- popup 模式：检查 `osascript` 是否被你 OS 设置允许（macOS 隐私设置）。

**统计为 0 / 不增长？**

- 动画进程每 5 秒才 flush 一次到磁盘，至少跑满 5 秒才会有累加。
- 跑 `cat ~/.claude/plugins/data/claude-coach/stats.json` 直接看。

**窗口残留不关？**

- 用 `tmux kill-pane`（tmux 模式）或手动关掉那个窗口。
- 下次 `claude` 启动时 `SessionStart sweep` 会清理同会话的 runtime 文件。

**想完全关掉这个插件一会儿**

- 在 Claude Code 里 `/plugin disable claude-coach`。

---

## 依赖

- `bash` 3.2+（macOS 自带就行）
- `jq` —— 用于读写 JSON
- 可选：`tmux`（用 tmux 模式时）
- macOS：`osascript`（系统自带）

---

## 许可

MIT
