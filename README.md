# AI CLI 設定資料

此儲存庫保存 Claude Code、Codex CLI 與 Antigravity CLI 的版本化設定，包含
規則、agents、commands、skills 與 MCP 設定。

## 目錄結構

```text
.
├── claude/
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── mcp.json
│   ├── statusline.sh
│   ├── rules/
│   ├── agents/
│   ├── commands/
│   └── shared/
│       ├── both/          # Codex 與 Antigravity 共用
│       ├── codex/         # Codex 專用
│       └── agy/           # Antigravity 專用
├── codex/
│   └── config.toml
└── agy/
    └── settings.json
```

`claude/shared/` 是跨工具 skill 的權威來源；各目標目錄只保存該工具專屬的
設定與覆寫。

## 資料邊界

此儲存庫不保存 credentials、`auth.json`、sessions、對話紀錄、SQLite、cache
或其他主機 runtime state。Codex 的 `[projects.*]` trust 設定也維持在各主機，
不納入版本控制。
