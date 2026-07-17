# ai-config-settings (myccskills)

此儲存庫集中管理 Claude Code、Codex CLI 與 Antigravity CLI 的個人設定資料，
包含個人工作流、客製規則、skills 與 agents。

> [!IMPORTANT]
> 本儲存庫為私有資料 repo，預設位於公開工具 repo 內的
> `~/ai-config/data`。外層與內層各自保有獨立的 `.git`、remote 與提交歷史。

## Bootstrap

請先設定好存取私有 repo 的 SSH key，再執行：

```bash
git clone https://github.com/CSL426/ai-config.git ~/ai-config
AI_CONFIG_REPO_URL=git@github.com:CSL426/myccskills.git ~/ai-config/install.sh && ai-config apply
```

完成後的結構：

```text
~/ai-config/              # 公開工具 repo
├── .git/
├── ai_config/
└── data/                 # 本私有資料 repo
    ├── .git/
    ├── claude/
    ├── codex/
    └── agy/
```

`~/ai-config/data` 已由外層工具 repo 的 `.gitignore` 排除，不會被誤收進公開
repo。若資料必須放在其他位置，可設定 `AI_CONFIG_REPO`。

## 雙機工作流

### 在機器 A（修改設定側）

1. 執行 `ai-config status`，確認本機修改與 data repo 的差異。
2. 執行 `ai-config init [tool]`，把預期的本機變更收進 data repo。
3. 在 `~/ai-config/data` 檢查、commit 並 push。

### 在機器 B（同步部署側）

1. 執行 `ai-config sync [tool]`，拉取 data repo 並顯示差異。
2. 確認差異後執行 `ai-config apply [tool]`。

## 目錄地圖

| 路徑 | 內容 | 部署目的地 |
|------|------|----------|
| `claude/` | Claude Code 設定 | `~/.claude/` |
| `claude/shared/both/<skill>/` | 跨工具 skill（權威副本） | Codex 與 agy |
| `codex/` | Codex CLI 設定與 skills | `~/.codex/` |
| `agy/` | Antigravity CLI 設定與 skills | `~/.gemini/antigravity-cli/` |

## 資料契約

- 此 repo 只保存會被同步的設定資料與本 README。
- 同步引擎、installer、測試、開發指南與 changelog 全部位於外層
  `~/ai-config` tool repo。
- credentials、auth、session、cache 與主機專屬 runtime state 不進 repo。
- 修改後先執行 `ai-config status`，確認投影範圍再決定 `init` 或 `apply`。
