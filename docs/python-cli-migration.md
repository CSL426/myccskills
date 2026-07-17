
# ai-config Python CLI 遷移計畫

**狀態:Draft**(依規範,未經使用者確認完成前不得標記 Done)
**建立日期:2026-07-16**

---

## 1. 目標與非目標

### 目標

- 以**單一 Python 實作**取代目前的雙實作(`ai-config.sh` 850 行 + `ai-config.ps1` 2309 行 + `scripts/*.sh` 314 行,共約 3473 行),Linux 與 Windows 共用同一份程式碼。
- 消滅「用 shell 處理結構化資料」的整類 bug:JSON/TOML/YAML 一律改用真 parser。
- 指令介面與行為**完全不變**:`init` / `apply` / `status` / `list` / `reset` / `project`,輸出格式盡量貼近現版。
- 現有 pytest 測試套件作為**行為對等的驗收標準**,遷移完成的定義是全數通過。

### 非目標(遷移期間明確不做)

- 不新增任何功能(plugin manifest 方案 B、agy trustedWorkspaces 排除等,遷移後另案)。
- 不改變 repo 目錄結構與 source-of-truth 模型。
- 不打包上 PyPI、不做安裝器;維持「clone repo 直接執行」。

## 2. 動機:雙實作的實際成本(2026-07-16 一日實錄)

| 事件                                       | 根因                                                                                         | 單一 Python 實作下    |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- | --------------------- |
| status/apply 默默以 exit 141 中斷          | bash`pipefail` + `grep -q`/`awk exit` 早退 SIGPIPE,67KB SKILL.md 超過 64KB pipe buffer | 不存在(無 pipeline)   |
| hallmark frontmatter 被疊兩層垃圾          | 同上,SIGPIPE 誤判「無 frontmatter」                                                          | 不存在                |
| short-description 產生未閉合 quoted scalar | awk 土法切字串,把結尾引號切掉;**ps1 版早已寫對** → 雙實作漂移實證                     | 真 YAML 序列化,不存在 |
| statusline.sh 納管改 8 處                  | sh 兩處清單 + ps1 七處硬編碼清單                                                             | 改 1 處常數           |
| plugin drift 偵測只有 sh 版                | 新功能必須寫兩次                                                                             | 寫一次                |

## 3. 目標架構

```
ai-config/
├── ai-config.sh          # 薄殼:exec python3 -m ai_config "$@"
├── ai-config.ps1         # 薄殼:python -m ai_config @args
├── ai_config/
│   ├── __main__.py       # argparse 進入點與指令分派
│   ├── console.py        # 顏色/log_* 輸出(對齊現版格式)
│   ├── paths.py          # 工具 home、CODEX_SHARED_HOMES、排除清單等常數
│   ├── frontmatter.py    # SKILL.md 正規化(取代 sanitize_skill_frontmatter)
│   ├── staging.py        # stage projection(claude/codex/agy 共用骨架)
│   ├── skills.py         # sync_skills、reconcile_managed_skills、shared mirror
│   ├── links.py          # 平台連結策略:Linux symlink / Windows Junction+copy-fallback
│   ├── backup.py         # 備份與 prune
│   ├── plugins.py        # plugin drift 偵測
│   └── tools/
│       ├── claude.py     # init/apply/status 的 claude 專屬邏輯
│       ├── codex.py      # config.toml filter/merge、shared homes
│       └── agy.py        # mcp_config、canonical skills store
└── tests/                # Linux 全套 + Windows native contract
```

### 關鍵設計決策

1. **Python 版本**:>= 3.11(`tomllib` 內建;兩台機器均為 3.12)。Windows 端需確認 `python` 在 PATH(Git Bash 薄殼可自動偵測 `python3`/`python`/`py -3`)。
2. **依賴策略**:stdlib-only 優先。YAML frontmatter 僅需讀寫「name / description / metadata 小子集」,自寫最小 parser(沿用現版行為),**不引入 pyyaml**;若後續需求變複雜再評估。
3. **config.toml merge**:維持現版**逐行文字處理**語意(filter `[projects.*]` / merge 保留),不用 tomlkit——現版行為有測試鎖定,文字處理最不易產生意外 diff。
4. **Windows 連結策略**:從 ps1 移植(最高風險區):Junction 優先(`_winapi.CreateJunction` 或 `subprocess mklink /J`)、失敗時 copy fallback、ownership fingerprint 判斷可否覆蓋。Linux 維持 symlink。
5. **薄殼保留**:`ai-config.sh` / `ai-config.ps1` 檔名與用法不變,內部轉呼叫 `python -m ai_config`,使用者體驗零改變。Git Bash 情境由 .sh 薄殼直接處理(不再需要委派 powershell.exe)。
6. **輸出對齊**:log 符號(✓/⚠/✗/ℹ)、`═══ Status: tool ═══` 標題格式照舊,讓肉眼與既有測試斷言都無感。

## 4. 遷移階段

### 目前進度快照(2026-07-17)

- Python CLI 的 claude/codex/agy 投影、status、mirror/plugin drift、list/reset/project 已有可執行實作,不是只有架構骨架。
- 本輪已補齊跨程序 apply lock、全工具先 stage 再 mutation、失敗 exit code、單一原子 backup snapshot、completed ownership marker 與安全 prune。
- frontmatter 已改採 ps1 基準:CRLF 正規化、合成 name 單引號、未閉合引號改寫、short-description 插入既有 metadata block 內。
- shared skill supporting dirs 已包含 `examples/`、`references/`、`scripts/`、`agents/`;manifest orphan prune 會拒絕 traversal 名稱。
- Linux 上的完整 Python 測試結果:`119 passed, 1 skipped`;Python 3.11 與 3.12 結果一致,唯一 skip 是只能在 Windows 驗證的原生 Junction 案例。
- Windows 測試 harness 已改接 Python CLI;一般 Windows 行為以 deterministic copy fallback 在 Linux 驗證,原生 Windows Junction 另有平台限定測試。
- 薄殼已切換到 Python,舊 sh/ps1 實作已移入 `legacy/`;目前剩餘阻塞是原生 Windows 實機/CI 與兩台實機 `status` → `apply` → `status` 驗證。

### Phase 0 — 行為凍結與測試補強(先行,約半天)

- [x] 盤點現版 sh/ps1 的行為差異清單 → `docs/sh-ps1-behavior-notes.md`。
- [x] 為尚無測試覆蓋的行為補測試:`reset`、`project`、backup prune、codex shared home links、冪等(`tests/test_commands.py`,8 條);plugin drift codex 端原已有測試。
- [x] 測試 harness 抽象化:`AI_CONFIG_IMPL=sh|ps1|py` 環境變數切換受測實作,`run_ai_config()` 並支援 stdin(reset 互動測試用)。

### Phase 1 — 核心 + claude(約一天)

- [x] `console` / `paths` / `frontmatter` / `staging` / `backup` 模組。
- [x] `init claude` / `apply claude` / `status claude` 全綠。
- [x] frontmatter 正規化以 ps1 語意為準(單引號 scalar、引號剝除規則)。

### Phase 2 — codex + agy + 連結策略(約一天)

- [x] codex:config.toml filter/merge、AGENTS.md 投影、shared homes 連結。
- [x] agy:mcp_config、canonical skills store、orphan pruning。
- [ ] `links.py` 雙平台實作已完成;copy fallback 已由 Linux harness 驗證,仍待 Windows 實機驗證原生 Junction。

### Phase 3 — status 附加檢查(約半天)

- [x] shared mirror drift(`mirror-of`/`mirror-hash`)。
- [x] plugin drift(agy registry + codex config)。
- [x] repo/live mtime 與 newer-side 提示;mtime-preserving staging/apply。
- [x] `list` / `reset` / `project`。

### Phase 4 — 切換與退役(約半天)

- [ ] Linux 全套已全綠(`119 passed, 1 skipped`,Python 3.11/3.12);Windows native contract workflow 已就緒,仍待 CI 實際跑完原生 Junction 測試。
- [ ] 兩台實機各跑一輪 `status` → `apply` → `status`,確認冪等且無非預期 diff。
- [x] 薄殼替換;舊實作移至 `legacy/`(保留一個 release 週期後刪除)。
- [x] 更新 README、CLAUDE.md、ai-config-sync skill 中涉及實作的描述。

## 5. 風險與對策

| 風險                                   | 等級 | 對策                                                                                  |
| -------------------------------------- | ---- | ------------------------------------------------------------------------------------- |
| Windows Junction/fallback 語意移植失真 | 高   | Phase 0 先補測試;Phase 2 在 Windows 實機驗證;ownership fingerprint 演算法逐行對照 ps1 |
| 輸出格式微差導致測試斷言失敗           | 中   | 斷言以行為(檔案內容/exit code)為主,輸出字串斷言僅保留關鍵字                           |
| 兩機`.git/` 檔案同步干擾遷移分支     | 中   | **先解決 .git 同步問題**(排除 `.git/`,commit 集中單機)再開工                  |
| Windows 無 python 或版本過舊           | 低   | 薄殼偵測並給明確錯誤訊息(仿現版 Git Bash guard 的做法)                                |
| 冪等性回歸(apply 兩次產生 diff)        | 中   | Phase 4 加入「apply → status 必須全綠」的自動化測試                                  |

## 6. 驗收清單

- [ ] Linux `pytest tests/` 全數通過;Windows native contract 在 Python 3.11/3.12 全數通過且原生 Junction 案例不得 skip。Unix shell wrapper 與 legacy PowerShell contract 各在對應平台執行。
- [ ] 兩台實機 `status` 全綠、`apply` 冪等。
- [x] 舊版今日修過的三個 bug(SIGPIPE、frontmatter 疊加、short-description 引號)各有對應 regression 測試且通過。
- [ ] 使用者確認後,本文件狀態改為 Done。

## 7. 遷移後另案(不在本計畫範圍)

- [x] pipx 可安裝封裝 (已完成)
- [x] `sync` 子命令支援 (已完成)
- plugin manifest(方案 B):跨 CLI plugin 對照表 + apply 強制對齊。
- agy `trustedWorkspaces` 比照 codex `[projects.*]` 排除出同步。
- **project 模式的 plugin 鏡射要過濾**:`stage_agy_projection` 目前把 `~/.claude/plugins/` 整包鏡射給 agy,包含 Claude registry 裡「已安裝但非 ai-config 管理意圖」的 plugin(例如僅供某專案 project-scope 使用的 agent-sdk-dev),導致 agy 端殭屍復活(2026-07-16 實案)。應改為只鏡射 repo `claude/settings.json` enabledPlugins 列出的 key,與 plugin drift 檢查的「意圖」定義一致。
- ps1 時代遺留的七處硬編碼清單教訓 → 常數集中化已由架構自然解決。
