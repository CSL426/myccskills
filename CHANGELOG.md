# Changelog

本專案的重要變更會記錄在此檔案。

## [Unreleased]

### Added

- 新增 Python 3.11+ 共用 CLI 核心,統一 Linux、Windows 的 `init`、`apply`、`project`、`status`、`list`、`reset` 行為。
- 新增 `pyproject.toml` 與 `ai_config/cli.py`，支援透過 `pipx` 進行本機可開發式（editable）安裝，提供全域 `ai-config` 指令。
- 新增 `sync` 子命令，支援自動執行 `git pull --rebase --autostash` 並顯示狀態差異。
- 新增 Python 版 Windows Junction、ownership-safe copy fallback、原子備份、apply lock、reparse/path traversal 防護與跨平台 contract tests。
- 新增 Ubuntu/Windows 的 Python 3.11 與 3.12 CI 矩陣。
- 新增原生 Windows `ai-config.ps1`，支援 Windows PowerShell 5.1 與 PowerShell 7，不依賴 WSL、Bash 或 `rsync`。
- PowerShell CLI 支援 `init`、`apply`、`project`、`status`、`list`、`reset`，並涵蓋 Claude Code、Codex CLI 與 Antigravity CLI。
- 新增 Windows 測試矩陣，分別以 Windows PowerShell 5.1 與 PowerShell 7 執行 pytest。
- `status` 新增 repo/live mtime 與 newer-side 提示,並標明時間只作為同步方向的輔助線索。

### Changed

- 根目錄 `ai-config.sh` / `ai-config.ps1` 改為 Python 薄 wrapper；舊完整 Bash/PowerShell 實作移至 `legacy/`,暫留一個 release 週期。
- JSON plugin registry/settings 處理改用 parser,不再用 regex 或整份字串替換。
- 以 `.gitattributes` 固定 shell script 使用 LF，避免 Windows checkout 產生 `bash\r` shebang 錯誤。
- 根目錄 `AGENTS.md` 與 `GEMINI.md` 由 symlink 改為普通檔案，並以測試維持其與 `CLAUDE.md` byte-identical，無需 Windows Developer Mode 或 Git symlink 設定。
- Windows 多 home 共用目錄優先使用 Junction；無法建立時改用具 ownership state 與內容 fingerprint 的安全複製 fallback。
- `status` 現在會預覽 exact mirror 與 managed skill manifest 將移除的 live-only 路徑；apply 中途失敗時會列出可恢復的 backup snapshot。
- `init all` 會先完成所有工具的 read-only preflight，再開始修改 repo，避免後段失敗留下部分收集結果。
- staging、apply、backup 與 Windows copy fallback 會保留來源檔案 mtime,避免同步本身製造假的「較新」時間。
- Codex `AGENTS.md` 可保留直接指向正常 `~/.claude/CLAUDE.md` 的共享 symlink；其他目標、broken/chained link 與 Codex 專屬覆寫仍會拒絕。
- apply backup 只收錄本次 stage 可能修改的路徑，避免未投影的 plugin cache 或其他 live-only 目錄造成大量無效 I/O。

### Security

- PowerShell 部署加入受管理來源、目的地、備份、manifest 與 ownership state 的 reparse point、path traversal 與來源一致性檢查。
- 備份採 ownership marker、原子完成與 apply lock；只輪替本工具擁有的完成 snapshot，並保留外來或未完成目錄。
- copy fallback 不覆蓋未受管理、ownership 不符或 fingerprint 已變更的路徑。
- credential 排除同時套用於收集、部署與備份。
- backup root、apply lock 與 snapshot prune 會拒絕 Windows Junction / reparse point；managed skill 與 plugin mirror 會保留排除的 credential。
- plugin mirror 與對應 backup 允許目標仍位於 plugin root 的相對 symlink；absolute、broken、Junction 或逃逸 root 的連結會在 live mutation 前拒絕。
