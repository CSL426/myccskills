# Changelog

本專案的重要變更會記錄在此檔案。

## [Unreleased]

### Added

- 新增原生 Windows `ai-config.ps1`，支援 Windows PowerShell 5.1 與 PowerShell 7，不依賴 WSL、Bash 或 `rsync`。
- PowerShell CLI 支援 `init`、`apply`、`project`、`status`、`list`、`reset`，並涵蓋 Claude Code、Codex CLI 與 Antigravity CLI。
- 新增 Windows 測試矩陣，分別以 Windows PowerShell 5.1 與 PowerShell 7 執行 pytest。

### Changed

- 以 `.gitattributes` 固定 shell script 使用 LF，避免 Windows checkout 產生 `bash\r` shebang 錯誤。
- 根目錄 `AGENTS.md` 與 `GEMINI.md` 由 symlink 改為普通檔案，並以測試維持其與 `CLAUDE.md` byte-identical，無需 Windows Developer Mode 或 Git symlink 設定。
- Windows 多 home 共用目錄優先使用 Junction；無法建立時改用具 ownership state 與內容 fingerprint 的安全複製 fallback。

### Security

- PowerShell 部署加入受管理來源、目的地、備份、manifest 與 ownership state 的 reparse point、path traversal 與來源一致性檢查。
- 備份採 ownership marker、原子完成與 apply lock；只輪替本工具擁有的完成 snapshot，並保留外來或未完成目錄。
- copy fallback 不覆蓋未受管理、ownership 不符或 fingerprint 已變更的路徑。
- credential 排除同時套用於收集、部署與備份。
