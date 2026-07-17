# sh / ps1 行為差異盤點(Python 版語意基準)

Phase 0 產出。逐項記錄兩實作的已知差異,以及 Python 版該採用哪一邊的語意。
「採用」欄位:`ps1` = 以 PowerShell 版為準;`sh` = 以 Bash 版為準;`平台` = 依平台分流。

## frontmatter 正規化(sanitize_skill_frontmatter / ConvertTo-SkillDocument)

| 項目 | sh | ps1 | 採用 |
|------|----|----|------|
| 合成 `name` scalar | 裸值(`name: Bare Agent`) | 單引號(`name: 'Bare Agent'`) | **ps1**(對特殊字元安全;現有 sh 測試斷言需同步改) |
| 合成 `short-description` | 單引號(2026-07-16 已對齊 ps1) | 單引號 `ConvertTo-YamlScalar` | ps1(已一致) |
| description 引號剝除 | 完整 `"..."` 且無內部 `"`/`\` → 剝;開頭引號但不完整 → 退回 name | 同 | 一致 |
| description 改寫為 `>-` 的跳過條件 | 開頭為 `\|`、`>`、`'`、`"` 即跳過 | 僅「完整被引號包住」(`^(["']).*\1$`)或 `^[>\|]` 才跳過;**開頭引號但不完整仍會改寫** | **ps1**(語意較精確) |
| 換行處理 | 依賴輸入為 LF | 先正規化 CRLF/CR → LF | **ps1**(Python 版一律正規化) |

## apply / init 基礎設施

| 項目 | sh | ps1 | 採用 |
|------|----|----|------|
| apply 鎖 | 無 | `Enter-ApplyLock`(防並發 apply) | **ps1**(跨平台實作) |
| 路徑安全檢查 | 無 | reparse point 拒絕、`Assert-SafeWriteTarget`、contained-child 檢查 | **ps1**(Python 版全平台啟用,symlink 檢查取代 reparse 檢查) |
| 檔案寫入編碼 | 依系統 | `Write-Utf8File`(無 BOM UTF-8) | **ps1**(Python 明確 `utf-8`、`newline="\n"`) |
| 備份快照 | `BACKUP_BASE/<ts>/<tool>`,`BACKUP_KEEP=5` | `Get-CompletedBackupSnapshots` + `Remove-OldBackupSnapshots`(有 completed 標記概念) | **ps1** 的 completed 標記 + sh 的簡單 prune 數量(=5);細節移植時對照 |
| codex config.toml filter/merge | 逐行文字處理(`[projects.*]` 保留) | `Get-CodexProjectsBlock` / `Get-CodexGeneralConfigContent`(同語意) | 一致(逐行文字處理) |

## 連結策略(平台分流,links.py)

| 項目 | sh(Linux) | ps1(Windows) |
|------|-----------|---------------|
| codex 多 home 共用 | symlink(`ensure_codex_shared_links`);既有 symlink 指向他處 → 保留 + 警告 | Junction 優先 → copy fallback + ownership fingerprint(`Sync-CodexAlternateHomes`) |
| agy canonical skills | `AGY_HOME/skills` symlink → `~/.gemini/antigravity/skills` | `Sync-AgySkillsSurface`(Junction/fallback 同上) |
| 覆蓋保護 | 只看「是否為指向預期目標的 symlink」 | ownership state 檔 + 內容 fingerprint,非本工具擁有或 fingerprint 變更 → 拒絕覆蓋 |

Python 版:Linux 走 symlink 語意、Windows 走 Junction+fallback 語意,ownership fingerprint 演算法(`Get-FileFingerprint`/`Get-DirectoryFingerprint`/`Read-OwnershipState`)逐行對照 ps1 移植。

## 單邊獨有功能

| 功能 | 存在於 | Python 版 |
|------|--------|-----------|
| plugin drift 偵測(status) | sh(2026-07-16 新增) | 收錄 |
| Git Bash → powershell.exe 委派 | sh | 廢除(薄殼直接呼叫 python) |
| shared mirror drift(mirror-of/hash) | 兩邊皆有(`check_shared_mirrors` / `Show-SharedMirrorDrift`) | 收錄,輸出格式以 sh 為準 |
| `status` codex config 過濾比對 | 兩邊皆有 | 收錄 |

## 已知歷史 bug(regression 測試已鎖定,Python 版不得復發)

1. SIGPIPE / 64KB pipe buffer 使 status/apply 靜默中斷(sh,已修)。
2. 大檔誤判「無 frontmatter」疊加垃圾 frontmatter(sh,已修)。
3. 帶引號 description 合成出未閉合 short-description scalar(sh,已修;`test_quoted_description_yields_valid_short_description`)。

## Python 版目前落實狀態(2026-07-16)

已落實:

- apply/project 使用跨程序 lock;所有選定工具先完成 stage,任一失敗即不建立 backup、不修改 live 目錄,並回傳非零 exit code。
- backup 先寫入 `.tmp-<uuid>`,完成後加 `.ai-config-backup-owned` marker 再原子 rename;prune 僅處理合法名稱且 marker 正確的 completed snapshots。
- frontmatter 已採本文件的 ps1 語意,並把新增的 `short-description` 插在既有 metadata block 結尾,不會落到其他 top-level field 之下。
- managed source/destination 已有跨平台 symlink preflight;skill manifest traversal 名稱會被拒絕。
- mirror metadata parser 支援 quoted scalar、CRLF 與大小寫 hash 比對。
- Windows reparse/Junction/copy fallback 已移植;fallback 使用 ownership state、內容 fingerprint 與 completed marker 保護,拒絕覆蓋未納管或遭竄改的目的地。
- `tests/test_windows_sync.py` 已預設改接 Python CLI;Linux 以 forced copy fallback 驗證 Windows 行為,另保留原生 Windows Junction 平台測試。
- 根目錄 sh/ps1 已改為 Python 3.11+ 薄殼,舊版完整實作移至 `legacy/`。
- status 會預覽 exact mirror 與 managed skill manifest 將刪除的 live-only 路徑;手動安裝的 skill 與 credential 排除項不會誤報。
- managed mirror 刪除錯誤會使 apply 失敗;若備份後才失敗,輸出會指出可能部分更新及可人工恢復的 snapshot。
- `init all` 會先 preflight 所有選定工具,避免後段工具缺失或路徑不安全時前段已先改寫 repo。
- status 會顯示 repo/live mtime 與 newer-side 提示;staging/apply 保留來源 mtime。此資訊只協助判斷編輯先後,不取代 source-of-truth 決策。
- Codex `AGENTS.md` 若是直接指向正常 `~/.claude/CLAUDE.md` 的 symlink,apply 會保留並沿用此共享關係;foreign、broken、chained link 與 Codex 專屬覆寫一律拒絕。
- plugin mirror/backup 保留未逃出 plugin root 的相對 symlink;absolute、broken、Junction 或最終逃逸 root 的 link 會在 mutation 前拒絕。backup 只處理本次 stage 可能修改的路徑。

尚待實機驗證:

- 在原生 Windows 執行 Junction 測試,確認 `_winapi.CreateJunction` 與 ownership state 的實際結果。
- 在兩台實機各跑 `status` → `apply` → `status`,確認 live 設定投影冪等且無非預期差異。
