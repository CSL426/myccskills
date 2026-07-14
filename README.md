# ai-config

集中管理多個 AI coding assistant 的設定檔，用 Git 做版本控制，方便跨機器同步。

## 支援的工具

| 資料夾 | 工具 | Home 目錄 | 管理的檔案 |
|--------|------|-----------|-----------|
| `claude/` | Claude Code | `~/.claude/` | CLAUDE.md, settings.json, mcp.json, rules/, agents/ |
| `codex/` | Codex CLI | `~/.codex/` | AGENTS.md, config.toml, rules/, skills/ |
| `agy/` | Antigravity CLI | `~/.gemini/antigravity-cli/` | settings.json, mcp_config.json, skills/ |

Codex 以 `~/.codex/` 作為共用設定來源；`~/.codex-csl/`、`~/.codex-set/` 只保留各自的 auth/session/cache 狀態，`AGENTS.md`、`config.toml`、`rules/`、`skills/`、`plugins/`、`prompts/` 透過 symlink 共用 `~/.codex/`。

## 快速開始

### 自己用（跨機器同步）

```bash
git clone <repo-url> ~/ai-config
cd ~/ai-config
./ai-config.sh init       # 收集目前機器的設定
git add -A && git commit -m "chore: sync configs"
```

### 別人用（從頭開始）

```bash
git clone <repo-url> ~/ai-config
cd ~/ai-config
./ai-config.sh reset      # 清空範例設定，只留空骨架
./ai-config.sh init       # 拉自己的設定進來
```

## 指令

```
./ai-config.sh <command> [tool]
```

| 指令 | 說明 |
|------|------|
| `init [tool]` | 從各工具的 home 目錄收集設定到 repo |
| `apply [tool]` | 從 repo 部署設定到各工具的 home 目錄 |
| `status [tool]` | 比對 repo 與目前生效的設定差異 |
| `list` | 列出管理中的工具及檔案數量 |
| `reset` | 清空所有設定檔，只留空目錄骨架 |

`tool` 可以是 `claude`、`codex`、`agy` 或 `all`（預設）。

## 範例

```bash
./ai-config.sh init claude       # 只收集 Claude 的設定
./ai-config.sh apply codex       # 只部署 Codex 的設定
./ai-config.sh status agy        # 查看 Antigravity CLI 差異
./ai-config.sh list              # 列出管理狀態
./ai-config.sh reset             # 清空所有設定（會確認）
```

## 安全機制

- **自動備份** — 每次 `apply` 前會備份到 `~/.ai-config-backup/<timestamp>/`
- **憑證排除** — `.credentials.json`、`auth.json`、`oauth_creds.json`、`google_accounts.json`、`trustedFolders.json` 永遠不會被複製
- **Codex projects 保留** — `apply` 時會保留目標機器的 `[projects.*]` 區塊，只更新通用設定
- **Codex 多 home 共用設定** — `apply codex` 會補齊 `.codex-csl` / `.codex-set` 到 `~/.codex` 的 managed path symlink，但不覆蓋已存在的實體檔或不同 symlink

## 目錄結構

```
ai-config/
├── ai-config.sh          # CLI 主程式
├── claude/
│   ├── CLAUDE.md          # 全域指令
│   ├── settings.json      # Claude Code 設定
│   ├── mcp.json           # MCP server 設定
│   ├── agents/            # 自訂 agent 定義
│   └── rules/             # 共用 / 語言專屬規則
│       ├── common/
│       └── typescript/
├── codex/
│   ├── AGENTS.md          # Codex 全域指令
│   ├── config.toml        # Codex 設定（不含 projects）
│   ├── rules/
│   └── skills/            # 只同步 SKILL.md + examples/ + references/
└── agy/
    ├── settings.json      # Antigravity CLI 設定
    ├── mcp_config.json    # MCP server 設定
    └── skills/            # 只同步 SKILL.md + examples/ + references/
```

## 典型工作流程

1. 在任一台機器修改設定（例如加一條 rule）
2. `./ai-config.sh init` 收集變更
3. `git commit` + `git push`
4. 在其他機器 `git pull` + `./ai-config.sh apply`
