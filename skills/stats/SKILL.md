---
description: 显示 claude-coach 累计运动时长与最近 7 天柱状图
---

执行 `${CLAUDE_PLUGIN_ROOT}/bin/render-stats.sh` 并把它的输出**原样**展示给用户。

- 不要重新格式化、不要翻译、不要总结。
- 如果脚本失败或输出为空，把脚本的 stderr 也展示给用户。
- 调用方式（在 Bash 工具里运行）：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/render-stats.sh"
```
