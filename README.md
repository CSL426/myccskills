# ai-config

集中管理 Claude Code、Codex CLI 與 Antigravity CLI 的設定，以 Git repository 作為 source of truth，方便在不同作業系統與機器之間同步。

## 支援平台

- Windows 11：`ai-config.ps1` 薄 wrapper 呼叫共用 Python CLI,不需要 WSL、Bash 或 `rsync`。
- Linux / 相容 Unix 環境：`ai-config.sh` 薄 wrapper 呼叫同一份 Python CLI。
- 兩個平台都需要 Python 3.11 或更新版本；核心使用 Python standard library,執行 CLI 不需額外套件。

| 資料夾 | 工具 | Home 目錄 | 主要管理內容 |
|--------|------|-----------|--------------|
| `claude/` | Claude Code | `~/.claude/` | `CLAUDE.md`、`settings.json`、`mcp.json`、`rules/`、`agents/`、`commands/` |
| `codex/` | Codex CLI | `~/.codex/` | `AGENTS.md`、`config.toml`、`rules/`、`skills/` |
| `agy/` | Antigravity CLI | `~/.gemini/antigravity-cli/` | `settings.json`、`mcp_config.json`、`skills/`、`plugins/` |

## 安裝與快速開始

本工具支援透過 `pipx` 進行本機可開發式（editable）安裝，安裝後即可在系統的任何目錄直接執行 `ai-config` 全域指令。

### 全域安裝模式 (推薦)

1. **複製本儲存庫**：
   ```bash
   git clone <repo-url> "$HOME/ai-config"
   cd "$HOME/ai-config"
   ```

2. **使用 pipx 安裝**（重點：指定**系統 Python** 建 venv,不要讓指令綁死在 pyenv / conda 等版本管理器的直譯器上——那些環境一換版本,指令就會斷）：
   * **Linux / macOS**：
     如果您之前已手動在 `~/.local/bin` 建立了別名或 symlink，請先移除它：
     ```bash
     rm -f ~/.local/bin/ai-config
     ```
     然後執行：
     ```bash
     pipx install --python /usr/bin/python3 --editable .
     ```
   * **Windows**：
     ```powershell
     pipx install --editable .
     ```
   * **沒有 pipx 的環境**（手動 venv,與 pipx 效果等價）：
     ```bash
     /usr/bin/python3 -m venv ~/.venvs/ai-config
     ~/.venvs/ai-config/bin/pip install --editable .
     ln -sf ~/.venvs/ai-config/bin/ai-config ~/.local/bin/ai-config
     ```
     *(避免 `pip install --user`：console script 的 shebang 會硬指當下的直譯器路徑,pyenv 換版本後指令即失效)*

3. **開始使用**：
   安裝後即可在任何目錄直接執行 `ai-config` 全域指令：
   ```bash
   # 檢查設定差異
   ai-config status

   # 拉取最新變更並檢查狀態
   ai-config sync

   # 部署設定到各工具的主目錄
   ai-config apply
   ```

### 現場執行模式 (免安裝)

若您不想將指令安裝到系統環境中，亦可直接執行儲存庫根目錄的 wrapper 腳本：
* **Linux / Unix**：使用 `./ai-config.sh`
* **Windows**：使用 `.\ai-config.ps1` (若提示 ExecutionPolicy 限制，可執行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` 解鎖)。

第一次要把現有機器的設定收進 repo 時，先執行 `status` 檢查範圍，再執行 `init`。`init` 會修改 repo 內的受管理設定；請在提交前檢查 `git diff`，不要直接把無關變更一起提交。

## 指令

`tool` 可為 `claude`、`codex`、`agy` 或 `all`；未指定時預設為 `all`。Antigravity 也接受 `antigravity`、`antigravity-cli` 與 `antigravity_cli` alias。

| 功能 | Bash | PowerShell | 說明 |
|------|------|------------|------|
| 收集設定 | `./ai-config.sh init [tool]` | `.\ai-config.ps1 init [tool]` | 從工具 home 收集受管理設定到 repo |
| 部署設定 | `./ai-config.sh apply [tool]` | `.\ai-config.ps1 apply [tool]` | 從 repo 部署到工具 home；執行前應先跑 `status` |
| 直接投影 | `./ai-config.sh project [tool]` | `.\ai-config.ps1 project [tool]` | 以目前的 `~/.claude/` 為來源，直接投影到 Codex / agy；不先寫回 repo |
| 檢查差異 | `./ai-config.sh status [tool]` | `.\ai-config.ps1 status [tool]` | 唯讀比較 repo 投影結果與目前生效設定，顯示雙方 mtime 先後提示，並檢查 shared skill mirror drift |
| 拉取與對照 | `./ai-config.sh sync [tool]` | `.\ai-config.ps1 sync [tool]` | 從遠端拉取最新變更（`git pull`），成功後自動執行 `status` 顯示設定差異 |
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

Linux / 相容 Unix 環境的額外 Codex home 清單由 `ai_config/paths.py` 的 `CODEX_SHARED_HOMES` 定義；不存在的目錄會自動略過。

Windows 不需要開啟 Developer Mode：

- 受管理目錄可建立 Junction 時，Python CLI 會以 Junction 共用 canonical 內容。
- Junction 不可用或目標是檔案時，會使用 copy fallback，並以 ownership state 與內容 fingerprint 判斷後續是否仍可安全更新。
- 未標記為本工具擁有、fingerprint 已變更或指向不同來源的內容不會被直接覆蓋。

Linux / 相容 Unix 環境則使用 symlink 共用相同設定。

## 安全機制

- **先檢查再部署**：標準流程是 `status` → 確認差異 → `apply`；`status` 不修改 repo、工具 home 或備份,並會列出 exact mirror 與 managed skill manifest 預定刪除的 live-only 路徑。
- **修改時間提示**：內容不同時,`status` 會列出 repo/live mtime 並標示 `repo newer`、`live newer` 或時間接近；投影與部署會保留來源 mtime。mtime 只供判斷先後,Git checkout 或外部 copy 仍可能改變它,不會據此自動覆蓋任何一側。
- **自動備份**：`apply` 與 `project` 在修改前，只備份本次 stage 可能修改的受管理內容到 `~/.ai-config-backup/<timestamp>/`；未投影的 plugin cache 不會產生無效的大型備份。只輪替本工具擁有且已完成的 snapshot，保留最新五份，不刪除外來或未完成目錄。
- **失敗可恢復**：若 apply 在建立 snapshot 後才失敗,CLI 會提示 live 設定可能只完成部分更新,並列出可人工恢復的 snapshot 路徑。
- **憑證排除**：`.credentials.json`、`auth.json`、`oauth_creds.json`、`google_accounts.json`、`trustedFolders.json` 不會被收集、部署或放入受管理備份。
- **Codex projects 保留**：部署 `config.toml` 時保留目標機器既有的 `[projects.*]` 區塊，只更新可攜的通用設定；`status` 也忽略本機 projects 差異。
- **ownership-safe fallback**：Windows copy fallback 只會更新仍符合既有 ownership record 與 fingerprint 的路徑，避免接管使用者自行建立或修改的內容。
- **路徑防護**：Python CLI 會先檢查受管理來源、目的地、備份與 ownership state 的 reparse point / path traversal 風險，再開始修改。

## Repository 結構

```text
ai-config/
├── ai-config.sh           # Linux / Unix Python wrapper
├── ai-config.ps1          # Windows PowerShell Python wrapper
├── ai_config/             # 共用 Python CLI 核心
├── legacy/                # 遷移前完整 Bash/PowerShell 實作(暫留一個 release 週期)
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

## 典型同步流程（雙機工作流範例）

在**機器 A**（修改設定側）：
1. 執行 `ai-config status`，確認本機修改與 repo 的差異。
2. 執行 `ai-config init [tool]`，把預期的本機變更收集回 repo。
3. 檢查 `git diff`，手動 commit 並 push 到遠端。

在**機器 B**（同步部署側）：
1. 執行 `ai-config sync [tool]`，這會自動從遠端進行拉取並顯示目前的 status 差異。
2. 確認差異無誤後，執行 `ai-config apply [tool]` 將新設定部署到對應的 AI 工具主目錄。

## 測試

測試需要 Python、pytest 與 PyYAML。主測試預設直接驗證 Python CLI：

```bash
python -m pip install pytest PyYAML ruff
python -m pytest tests/
ruff check ai_config tests
bash -n ai-config.sh legacy/ai-config.sh legacy/scripts/*.sh
```

Windows CI 會用 Python 3.11 與 3.12 跑相同 contract,包含原生 Junction 成功案例。遷移期另保留 Windows PowerShell 5.1 / PowerShell 7 的 legacy parity job：

```powershell
python -m pip install pytest PyYAML
$windowsTests = @(
    "tests/test_repository_invariants.py",
    "tests/test_windows_sync.py"
)

# Windows PowerShell 5.1 legacy parity
$env:PWSH = (Get-Command powershell.exe).Source
$env:AI_CONFIG_IMPL = "ps1"
python -m pytest @windowsTests

# PowerShell 7 legacy parity
$env:PWSH = (Get-Command pwsh.exe).Source
python -m pytest @windowsTests
```

GitHub Actions 會在 Ubuntu 與 Windows 上各以 Python 3.11 / 3.12 驗證正式 Python CLI；legacy PowerShell job 僅保留遷移期對等證據。實際 CI 結果以 GitHub Actions run 為準。
