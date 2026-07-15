# ai-config

集中管理 Claude Code、Codex CLI 與 Antigravity CLI 的設定，以 Git repository 作為 source of truth，方便在不同作業系統與機器之間同步。

## 支援平台

- Windows 11：原生支援 Windows PowerShell 5.1 與 PowerShell 7，不需要 WSL、Bash 或 `rsync`。
- Linux / 相容 Unix 環境：使用 Bash 版 CLI；需要 Bash、`rsync` 與 `sha256sum` 等既有命令列工具。

| 資料夾 | 工具 | Home 目錄 | 主要管理內容 |
|--------|------|-----------|--------------|
| `claude/` | Claude Code | `~/.claude/` | `CLAUDE.md`、`settings.json`、`mcp.json`、`rules/`、`agents/`、`commands/` |
| `codex/` | Codex CLI | `~/.codex/` | `AGENTS.md`、`config.toml`、`rules/`、`skills/` |
| `agy/` | Antigravity CLI | `~/.gemini/antigravity-cli/` | `settings.json`、`mcp_config.json`、`skills/`、`plugins/` |

## 快速開始

### Windows 11 原生 PowerShell

Windows PowerShell 5.1 與 PowerShell 7 都使用同一支 `ai-config.ps1`：

```powershell
git clone <repo-url> "$HOME\ai-config"
Set-Location "$HOME\ai-config"

# 只有目前的 ExecutionPolicy 阻擋本機 script 時才需要；設定只維持此 process。
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 先確認 repo 與本機設定的差異，再部署。
.\ai-config.ps1 status
.\ai-config.ps1 apply
```

`ai-config.ps1` 是純 PowerShell / .NET 實作，不會呼叫 Bash、`rsync` 或其他 GNU 工具，因此沒有 WSL 的機器也能直接使用。

### Linux / 相容 Unix 環境

```bash
git clone <repo-url> "$HOME/ai-config"
cd "$HOME/ai-config"

# 先確認 repo 與本機設定的差異，再部署。
./ai-config.sh status
./ai-config.sh apply
```

第一次要把現有機器的設定收進 repo 時，先執行 `status` 檢查範圍，再執行 `init`。`init` 會修改 repo 內的受管理設定；請在提交前檢查 `git diff`，不要直接把無關變更一起提交。

## 指令

`tool` 可為 `claude`、`codex`、`agy` 或 `all`；未指定時預設為 `all`。Antigravity 也接受 `antigravity`、`antigravity-cli` 與 `antigravity_cli` alias。

| 功能 | Bash | PowerShell | 說明 |
|------|------|------------|------|
| 收集設定 | `./ai-config.sh init [tool]` | `.\ai-config.ps1 init [tool]` | 從工具 home 收集受管理設定到 repo |
| 部署設定 | `./ai-config.sh apply [tool]` | `.\ai-config.ps1 apply [tool]` | 從 repo 部署到工具 home；執行前應先跑 `status` |
| 直接投影 | `./ai-config.sh project [tool]` | `.\ai-config.ps1 project [tool]` | 以目前的 `~/.claude/` 為來源，直接投影到 Codex / agy；不先寫回 repo |
| 檢查差異 | `./ai-config.sh status [tool]` | `.\ai-config.ps1 status [tool]` | 唯讀比較 repo 投影結果與目前生效設定，並檢查 shared skill mirror drift |
| 列出狀態 | `./ai-config.sh list` | `.\ai-config.ps1 list` | 列出各工具的受管理檔案數與完成的備份數 |
| 清空 repo 設定 | `./ai-config.sh reset` | `.\ai-config.ps1 reset` | 經確認後清空 repo 內設定，只保留目錄骨架 |

`project all` 只會投影到 Codex 與 agy，因為 Claude 是來源。範例：

```powershell
.\ai-config.ps1 status codex
.\ai-config.ps1 init claude
.\ai-config.ps1 apply agy
.\ai-config.ps1 project codex
.\ai-config.ps1 list
.\ai-config.ps1 reset
```

## Windows 多 home 與連結策略

Codex 的 `~/.codex/` 是 canonical 設定來源；`~/.codex-csl/` 與 `~/.codex-set/` 保留各自的 auth、session 與 cache。Antigravity skill 的 canonical 位置是 `~/.gemini/antigravity/skills/`，CLI surface 位於 `~/.gemini/antigravity-cli/skills/`。

Linux / 相容 Unix 環境的額外 Codex home 清單由 `ai-config.sh` 的 `CODEX_SHARED_HOMES` 定義；不存在的目錄會自動略過。

Windows 不需要開啟 Developer Mode：

- 受管理目錄可建立 Junction 時，PowerShell 版會以 Junction 共用 canonical 內容。
- Junction 不可用或目標是檔案時，會使用 copy fallback，並以 ownership state 與內容 fingerprint 判斷後續是否仍可安全更新。
- 未標記為本工具擁有、fingerprint 已變更或指向不同來源的內容不會被直接覆蓋。

Linux / 相容 Unix 環境的 Bash 版則使用 symlink 共用相同設定。

## 安全機制

- **先檢查再部署**：標準流程是 `status` → 確認差異 → `apply`；`status` 不修改 repo、工具 home 或備份。
- **自動備份**：`apply` 與 `project` 在修改前，會把存在的受管理內容備份到 `~/.ai-config-backup/<timestamp>/`；只輪替本工具擁有且已完成的 snapshot，保留最新五份，不刪除外來或未完成目錄。
- **憑證排除**：`.credentials.json`、`auth.json`、`oauth_creds.json`、`google_accounts.json`、`trustedFolders.json` 不會被收集、部署或放入受管理備份。
- **Codex projects 保留**：部署 `config.toml` 時保留目標機器既有的 `[projects.*]` 區塊，只更新可攜的通用設定；`status` 也忽略本機 projects 差異。
- **ownership-safe fallback**：Windows copy fallback 只會更新仍符合既有 ownership record 與 fingerprint 的路徑，避免接管使用者自行建立或修改的內容。
- **路徑防護**：PowerShell 版會先檢查受管理來源、目的地、備份與 ownership state 的 reparse point / path traversal 風險，再開始修改。

## Repository 結構

```text
ai-config/
├── ai-config.sh           # Linux / 相容 Unix 環境的 Bash CLI
├── ai-config.ps1          # Windows 原生 PowerShell CLI
├── CLAUDE.md              # repository 層級共用指令
├── AGENTS.md              # 與 CLAUDE.md byte-identical 的普通檔案
├── GEMINI.md              # 與 CLAUDE.md byte-identical 的普通檔案
├── claude/
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── mcp.json
│   ├── agents/
│   ├── commands/
│   ├── rules/
│   └── shared/            # 投影到 Codex / agy 的跨工具 skill
├── codex/
│   ├── AGENTS.md
│   ├── config.toml        # repo 版本不含 [projects.*]
│   ├── rules/
│   └── skills/
├── agy/
│   ├── settings.json
│   ├── mcp_config.json
│   ├── plugins/
│   └── skills/
└── tests/
```

根目錄的 `CLAUDE.md`、`AGENTS.md` 與 `GEMINI.md` 都是普通檔案，不依賴 Windows symlink。測試會要求三者內容 byte-identical，修改共用指令時必須同步更新三份。

## 典型同步流程

在來源機器：

1. 執行 `status`，確認 live 設定與 repo 的差異。
2. 執行 `init [tool]`，把預期的 live 變更收進 repo。
3. 檢查 `git diff`，再自行 commit / push。

在其他機器：

1. `git pull`。
2. 執行 `status`，確認即將部署的差異。
3. 執行 `apply [tool]`。

## 測試

測試需要 Python、pytest 與 PyYAML。Windows 可分別指定 Windows PowerShell 5.1 或 PowerShell 7：

```powershell
python -m pip install pytest PyYAML
$windowsTests = @(
    "tests/test_repository_invariants.py",
    "tests/test_windows_sync.py"
)

# Windows PowerShell 5.1
$env:PWSH = (Get-Command powershell.exe).Source
python -m pytest @windowsTests

# PowerShell 7
$env:PWSH = (Get-Command pwsh.exe).Source
python -m pytest @windowsTests
```

Linux / 相容 Unix 環境若已安裝 PowerShell 7：

```bash
python -m pip install pytest PyYAML
PWSH="$(command -v pwsh)" pytest tests/
bash -n ai-config.sh scripts/*.sh
```

GitHub Actions 也會在 `windows-latest` 上分別以 Windows PowerShell 5.1 與 PowerShell 7 執行 Windows contract 與 repository invariant 測試。實際 CI 結果以 GitHub Actions run 為準。
