# TODO

## 現況

- `init` — 從各工具 home 目錄收集設定進 repo
- `apply` — 從 repo 部署設定到各工具 home 目錄（含從 `claude/` 投影共享內容）
- `status` — 比對 repo 與 home 目錄的差異
- `list` / `reset` — 輔助指令
- `sync` 已移除（原為空殼 compatibility command，功能已併入 `apply`）
- `rules/`、`commands/` 的 `apply` 改為不刪除 home 獨有的項目（與 `skills/` 行為一致）

## 未來想做

- [x] 新增一個指令，直接從 `~/.claude/` 投影到其他工具 home 目錄，不經過 repo (已新增 `project` 指令)
- [x] shared skill 鏡像 drift 偵測 — `status` 會檢查 `metadata.mirror-of` / `mirror-hash`，來源變了就警告 (2026-06)
- [x] `commands/` 納入 claude 受管目錄 (`CLAUDE_MANAGED_DIRS`)，`~/.claude/commands/` 有 git 備份了 (2026-06)
- [x] 補 sync 核心邏輯測試 — sanitize frontmatter、孤兒 skill 清理、drift 偵測、commands 投影 (`tests/test_sync_logic.py`)
- [x] 移除 `copilot/` — 不在 `ALL_TOOLS`，只是本機狀態快照，沒有同步價值
- [ ] mirror 過期時的一鍵刷新指令（目前是手動更新內容 + mirror-hash）
