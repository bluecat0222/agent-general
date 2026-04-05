# Bug Log — cc-restart.sh 重啟問題

## 2026-04-05

### Bug 1: tmux server 死亡後重啟失敗（已修復）

**時間**: 18:15 CST
**症狀**: `/restart` 觸發後 claude 關掉了但沒重開，3 次重試全部失敗
**原因**: kill claude 後 tmux server 跟著死掉。`start_claude_in_pane` 裡 `tmux list-panes` 回傳空值，`pane_alive` 為空字串，不等於 `"1"`，走了 send-keys 路徑，但 server 已死，send-keys 失敗。3 次重試都走同一條錯路。
**修復**: 加了 `pane_alive` 為空值時的處理 — kill session 然後 `tmux new-session` 重建。
**commit**: 尚未 commit

**Restart log**:
```
[18:15:09] kill_claude_in_pane: killing pane process 2782 (cmd=claude)
[18:15:12] start_claude_in_pane: session=cc dir=/Users/bxw/projects/agent-general pane_dead=
[18:15:12] start_claude_in_pane: using send-keys: ...
           no server running on /private/tmp/tmux-501/default
[18:15:27] attempt 1 failed
[18:15:27] attempt 2 — same failure
[18:15:42] attempt 3 — same failure
[18:15:57] all 3 attempts failed
```

---

### Bug 2: 重啟成功但 Claude 不回應 Discord（未解決）

**時間**: ~18:58 — 19:10+ CST
**症狀**: 重啟腳本成功啟動 claude（log 確認 `claude started successfully`），但 Discord 訊息完全沒回應。使用者從 19:10 開始問「重啟了嗎」一直到 20:04 都沒收到回覆。另一個 agent 確認 claude 進程確實在跑。
**原因**: 不明。可能是 Discord plugin 初始化失敗、bot 連線未建立、或 Claude 卡在某個狀態未處理 plugin 事件。
**狀態**: 未解決，無法重現（當前 session 正常）

**Restart log**:
```
[18:58:28] do_single: session=cc dir=/Users/bxw/projects/agent-general
[18:58:38] restart_one: killing claude in cc
[18:58:39] kill_claude_in_pane: killing pane process 99738 (cmd=claude)
[18:58:42] start_claude_in_pane: session cc gone, creating new session
[18:58:57] restart_one: [cc] claude started successfully
```

**Discord 訊息紀錄（無回應時段）**:
```
19:10:30 bluecat0222: 重啟了嗎
19:10:41 bluecat0222: ？
19:23:56 bluecat0222: 人勒
19:46:47 bluecat0222: 哈嘍？？
19:59:33 bluecat0222: 哈嘍？？
20:10:16 bluecat0222: 哈嘍        ← 這條才有回應（新 session 20:04 建立）
```

**Session 紀錄** (`/tmp/claude-501/-Users-bxw-projects-agent-general/`):
```
18:54  78d562fa-211d-4311-a62d-0a5978e20fee  ← 18:58 重啟建立的 session
20:10  155590ac-bcea-4cda-970e-e92d88e77d23  ← 當前 session（手動建立？）
```

**tmux session**: `cc: 1 windows (created Sun Apr 5 20:04:29 2026)` — 20:04 建立，restart log 無此記錄

---

## 待追蹤

- [ ] Bug 1 修復後需要實際測試 restart
- [ ] Bug 2 需要更多 logging 來診斷（plugin 初始化、Discord bot 連線狀態）
- [ ] 考慮在重啟腳本加健康檢查機制
