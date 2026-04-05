# agent-general

Claude Code 的通用工具集。

## cc-restart

Claude Code 自我重啟腳本，搭配 tmux 使用。

### 原理

Claude Code 無法自己重啟自己（進程死了就沒人拉起來）。這個腳本用 `nohup` fork 一個背景進程，等 claude 退出後再啟動新的。

### 使用方式

**單一 session 重啟**（claude 自己觸發，搭配 `/restart` skill）：

```bash
cc-restart.sh single <tmux-session> <project-dir>
```

**全部 session 重啟**（外部觸發）：

```bash
cc-restart.sh all
```

### 安裝

```bash
cp cc-restart/cc-restart.sh ~/bin/
cp cc-restart/SKILL.md ~/.claude/skills/restart/
chmod +x ~/bin/cc-restart.sh
```

### 流程

1. claude 呼叫 `cc-restart.sh single cc /path`
2. 腳本 fork 背景分身，立刻返回
3. claude 退出，shell 留在 tmux 裡
4. 背景分身等 10 秒
5. 用 `send-keys` 在 shell 裡啟動新的 claude
6. 最多重試 3 次，每次等 15 秒確認啟動成功
