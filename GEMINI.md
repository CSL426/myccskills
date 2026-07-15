# ai-config 專案指引

這個 repo 集中管理多個 AI CLI(Claude Code / Codex / Antigravity)的設定,是 **skill、agent、command、MCP、rule 的管理中樞**。在這裡工作的主要任務通常是:評估新資源 → 決定安裝位置 → 跑 `ai-config.sh`(Linux / Unix)或 `ai-config.ps1`(Windows)擴散到其他 CLI → 提交版本控制。

核心模型:**repo 是 source of truth**。`init` 把 live 設定收進 repo;`apply` 把 repo 設定部署到各工具 home 目錄。詳細指令見 `README.md` 與 `ai-config-sync` skill。

## 目錄地圖

| 路徑 | 內容 | 部署目標 |
|------|------|----------|
| `claude/` | CLAUDE.md, settings.json, mcp.json, rules/, agents/, commands/ | `~/.claude/` |
| `claude/shared/both/<skill>/` | 跨工具 skill(權威副本) | 鏡射到 Codex **與** agy |
| `claude/shared/codex/`、`claude/shared/agy/` | 單一工具專屬 skill | 只鏡射到該工具 |
| `codex/` | AGENTS.md, config.toml(不含 `[projects.*]`) | `~/.codex/` |
| `agy/` | settings.json, mcp_config.json, skills/ | `~/.gemini/antigravity-cli/` |
| `scripts/` | 各工具的 init/apply 實作(claude.sh / codex.sh / agy.sh) | — |
| `tests/` | sync 邏輯的 pytest 測試 | — |

Windows 11 原生流程使用根目錄的 `ai-config.ps1`,不需要 WSL、Bash 或 `rsync`;完整平台說明與指令對照見 `README.md`。

注意:`~/.claude/skills/` **不在同步範圍內**。要跨 CLI 的 skill 必須放 `claude/shared/`;要給 Claude Code 用則在 `~/.claude/skills/` 另放一份副本。

## 新增資源的決策表

| 要加的東西 | 放哪裡 |
|-----------|--------|
| 只給 Claude 用的 skill | `~/.claude/skills/<name>/`(不進 repo,不同步) |
| 跨 CLI 的 skill | `claude/shared/both/<name>/` + `~/.claude/skills/<name>/` 各一份 |
| Claude slash command | `~/.claude/commands/` → `init claude` 收進 repo(Codex/agy 沒有此概念,不要嘗試同步) |
| Claude subagent | `~/.claude/agents/` → `init claude` |
| MCP server | `~/.claude/mcp.json` → `init claude`;Codex/agy 各自的 MCP 設定另外評估 |
| 全域規則 | `~/.claude/rules/` 或 `~/.claude/CLAUDE.md` → `init claude` |

## 第三方 skill / plugin 評估清單

引入外部資源(GitHub repo、`npx skills add` 等)前,依序確認:

1. **來源與授權** — 作者可信度、star / 維護活躍度、授權允許使用(MIT/Apache 佳)。
2. **內容審查** — 讀過 SKILL.md 全文與 references 概要;確認沒有可疑指令(外洩資料、下載執行未知腳本、hardcoded 憑證或網址)。
3. **重疊分析** — 和現有 skill 的職責是否衝突(例如設計類已有 hallmark / ui-component-libraries / design-md 分工);重疊就先定調分工再裝,必要時更新全域 CLAUDE.md。
4. **觸發條件** — description 的觸發範圍會不會太寬、和別的 skill 搶觸發。
5. **形式判斷** — 規則型內容(要在主對話持續生效)做 skill;獨立、result-oriented 的任務才做 agent。
6. **更新策略** — 第三方 skill 保持原目錄結構、不改內容,方便日後從上游重新安裝更新;客製需求另寫自己的 skill 去引用它。

## 標準流程:新增跨 CLI skill

1. 評估(上面清單)→ 安裝到 `~/.claude/skills/<name>/` 驗證能被 Claude Code 註冊。
2. 複製到 `claude/shared/both/<name>/`(只會同步 `SKILL.md` + `examples/` + `references/` + `scripts/` + `agents/`)。
3. `./ai-config.sh status` — 每次 apply 前必跑,確認差異只有預期項目。
4. `./ai-config.sh apply` — 鏡射到 Codex / agy(自動備份到 `~/.ai-config-backup/`)。
5. 驗證:`ls ~/.codex/skills/<name>/`、`ls ~/.gemini/antigravity-cli/skills/<name>/`。
6. 給使用者看 `git status` 與擬提交內容,**經核准後才 commit/push**。

## 安全與紀律

- **credentials 永不進 repo**:`.credentials.json`、`auth.json`、`oauth_creds.json` 等腳本已自動排除;不要繞過。
- **`status` 先於 `apply`**:live 端有未收集的變更時,先 `init` 收進 repo,否則 `apply` 會把舊設定蓋回去。
- **不 bundle 無關變更**:commit 只包含本次任務動到的檔案;`init` 順帶收進來的其他 live 變更要向使用者說明、分開處理。
- **改 `ai-config.sh` / `ai-config.ps1` / `scripts/*.sh` 後必跑測試**:`pytest tests/`。
- shared skill 鏡像有 drift 偵測(`metadata.mirror-of` / `mirror-hash`),`status` 警告 mirror 過期時,更新內容並同步 mirror-hash。
