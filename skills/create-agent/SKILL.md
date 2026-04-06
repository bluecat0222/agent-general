---
name: create-agent
description: Create a new independent Claude Code agent session with its own Discord bot, project directory, and tmux window
user-invocable: true
---

# Create Agent — 建立獨立 Agent Session

When invoked, ask the user these 4 questions (one at a time, wait for each answer):

1. **Agent 名字？**（英文小寫，用於目錄名和 tmux window 名，例如 `product-manager`）
2. **用途？**（agent 的角色描述，會寫進 CLAUDE.md，例如「Senior Product Manager，負責 PRD、feature prioritization、roadmap planning」）
3. **Discord Bot Token？**（從 Discord Developer Portal 拿到的 token）
4. **Discord Channel ID？**（要綁定的��道 ID）

收集完 4 個答案後，執行以下步驟：

## Step 1: 建立專案目錄 + git init

```bash
mkdir -p /Users/bxw/projects/claude-code-agent/<agent-name>
cd /Users/bxw/projects/claude-code-agent/<agent-name>
git init
```

## Step 2: 建立 CLAUDE.md

在專案根目錄建 `CLAUDE.md`，根據用途生成 agent 人設。包含：
- Role 描述（基於用途回答）
- Language：Traditional Chinese (Taiwan) by default
- Style：Concise and direct, be opinionated
- Core Responsibilities（根據用途展開 3-5 項）
- Subagent Policy：需要搜尋時委派給 researcher

## Step 3: git commit

```bash
git add CLAUDE.md
git commit -m "Init <agent-name> agent with CLAUDE.md"
```

## Step 4: 設定 Discord State Directory

```bash
mkdir -p ~/.claude/channels/discord-<agent-name>
```

寫入 `.env`：
```
DISCORD_BOT_TOKEN=<token>
```

```bash
chmod 600 ~/.claude/channels/discord-<agent-name>/.env
```

寫入 `access.json`：
```json
{
  "dmPolicy": "allowlist",
  "allowFrom": ["1468991798444691549"],
  "groups": {
    "<channel-id>": {
      "requireMention": false,
      "allowFrom": ["1468991798444691549"]
    }
  },
  "pending": {}
}
```

## Step 5: 啟動 Agent

```bash
tmux new-window -n "<agent-name>" -c "/Users/bxw/projects/claude-code-agent/<agent-name>" "DISCORD_STATE_DIR=$HOME/.claude/channels/discord-<agent-name> claude -n <agent-name> --dangerously-skip-permissions --channels plugin:discord@claude-plugins-official"
```

## Step 6: 驗證

等待 10 秒後檢查：
```bash
tmux capture-pane -t cc:<agent-name> -p | tail -10
```

確認看到 Claude Code 啟動畫面和 MCP servers 連接。

## Step 7: 回報結果

告訴使用者：
- Agent 已建立並啟動
- 專案目錄位置
- Discord bot 綁定的頻道
- tmux window 名稱
- 提醒：到頻道發訊息測試
