# 工具/資料 repo 拆分計畫(ai-config 開源化)

**狀態:Draft**
**建立日期:2026-07-17**
**執行者:交由任一 coding agent 實作;本文件自足,不需其他對話上下文。**

---

## 0. 背景(現況)

私有 repo `CSL426/myccskills`(本機 `~/ai-config`)目前**同時**裝著兩種東西:

1. **工具**:`ai_config/` Python package(跨 AI CLI 設定同步引擎,stdlib-only,Python 3.11+)、`ai-config.sh`/`ai-config.ps1` 薄 wrapper、`install.sh`/`install.ps1` bootstrap installer、`pyproject.toml`(editable 安裝,console script `ai-config`)、`legacy/`(遷移前的 Bash/PowerShell 舊實作)、`tests/`、`.github/workflows/`。
2. **個人設定資料**:`claude/`、`codex/`、`agy/`、`claude/shared/`(跨工具 skills)——含個人工作流、主機路徑、live 服務 URL 等**不可公開**的內容。

因為資料不可公開,repo 必須維持私有,導致安裝體驗受限(不能匿名 `pipx install git+https://...`)。

**既有的關鍵地基**:`ai_config/paths.py` 已支援 `AI_CONFIG_REPO` 環境變數覆寫資料 repo 位置,且 `main()` 在 `SCRIPT_DIR/claude` 不存在時會報含解法的錯誤——拆分所需的「程式與資料分離」機制已存在,本計畫是把它從逃生口轉正為主幹設計。

## 1. 目標與非目標

### 目標

- 拆成兩個 repo:
  - **工具 repo(新建,公開)**:建議名 `CSL426/ai-config`。純程式,無任何個人資料。
  - **資料 repo(現有 `CSL426/myccskills`,維持私有)**:純設定資料。
- 全新機器 bootstrap 降到兩行:
  ```bash
  pipx install git+https://github.com/CSL426/ai-config.git
  git clone git@github.com:CSL426/myccskills.git ~/ai-config && ai-config apply
  ```
- 兩個 repo 各自測試全綠、各自 CI。

### 非目標

- 不發佈 PyPI(公開 git URL 安裝已滿足需求;PyPI 另案)。
- 不改變 CLI 指令介面與行為(`init/apply/status/list/reset/project/sync`)。
- 不做多使用者/多資料 repo 支援(單一資料 repo 假設不變)。

## 2. 拆分後架構

### 工具 repo `CSL426/ai-config`(公開)

```
ai-config/
├── pyproject.toml          # name=ai-config, console script
├── ai_config/              # 引擎(原樣搬移)
├── install.sh              # bootstrap(改:見 §3.3)
├── install.ps1
├── tests/                  # engine 測試(見 §3.4 拆分清單)
├── .github/workflows/      # python-cli.yml(ubuntu+windows × 3.11/3.12)
├── README.md               # 英文或中英,無個人資訊
└── LICENSE                 # MIT
```

### 資料 repo `CSL426/myccskills`(私有,瘦身後)

```
myccskills/  (~/ai-config)
├── claude/  codex/  agy/   # 設定資料(原樣)
├── CLAUDE.md / AGENTS.md / GEMINI.md   # repo 層指引(byte-identical 三份)
├── docs/                   # 計畫文件
├── tests/
│   └── test_repository_invariants.py  # 資料規則(三份指引一致等)
└── README.md               # 更新為兩行 bootstrap + 雙機工作流
```

**移除**:資料 repo 的 `ai_config/`、wrappers、installers、`pyproject.toml`、engine 測試、`legacy/`(遷移 parity 已完成階段性任務,直接刪除;歷史在 git)。

## 3. 工作項

### 3.1 資料 repo 定位邏輯轉正(`ai_config/paths.py`)

解析順序改為:

1. `AI_CONFIG_REPO` 環境變數(`expanduser().resolve()`);
2. `Path(__file__).parents[1]` **若其下有 `claude/` 目錄**(相容「工具還住在資料 repo 裡」的舊佈局與測試 fixture);
3. `~/ai-config` **若其下有 `claude/` 目錄**(拆分後的預設);
4. 皆無 → 延用現有錯誤訊息流程(提示 clone 資料 repo 或設 `AI_CONFIG_REPO`),`main()` 與 `console_main` 都要攔。

注意:`sync` 的 `git -C <資料repo>` 與 `list`/`reset` 等全部跟著這個解析走,不得殘留「工具 repo root」假設。

### 3.2 開源 sanitize(公開前必過)

工具 repo 內容全檔掃描,不得含:

- `myccskills`、`CSL426`(installer 的 REPO_URL 預設值改為**必填參數/環境變數**,README 用 `<your-config-repo-url>` placeholder)
- `/home/human`、實際主機名、`888box`、任何 live URL/token 字樣
- 個人化中文敘述(工具 README 重寫為中性文件)

驗收:`grep -riE "myccskills|csl426|/home/human|888box" <工具repo>` 零命中(測試 fixture 用中性假路徑)。

### 3.3 installer 調整

- `install.sh`/`install.ps1` 移入工具 repo,職責改為:「安裝工具本體」+「若 `AI_CONFIG_REPO_URL` 有給,順便 clone 資料 repo」。
- 公開後可提供匿名 one-liner(README):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/CSL426/ai-config/main/install.sh | bash
  ```
- 私有資料 repo 的 clone 仍走使用者的 SSH/gh 認證,installer 只透傳錯誤。

### 3.4 測試拆分

| 測試檔 | 去向 | 備註 |
|--------|------|------|
| `test_apply_projection.py`、`test_sync_logic.py`、`test_commands.py`、`test_python_migration.py`、`test_packaging_and_sync.py`、`test_wrappers.py`、`test_windows_sync.py`、`conftest.py` | 工具 repo | fake-HOME harness 本就自足;`AI_CONFIG_IMPL`/legacy parity 相關模式一併移除(py-only) |
| `test_repository_invariants.py` | 資料 repo | 補一個極簡 conftest;CI 用一支輕量 workflow 跑它 |

工具 repo 測試中所有建 fixture 的地方改用中性資料(不得引用資料 repo 實檔)。

### 3.5 資料 repo 收尾

- 刪除搬走的程式檔;`README.md` 改為:兩行 bootstrap、雙機工作流(A 機 `init`→commit/push;B 機 `ai-config sync`→`apply`)、資料目錄地圖。
- `CLAUDE.md`(repo 層)目錄地圖同步更新;「改 ai_config 後必跑測試」規則改指向工具 repo。
- `CHANGELOG.md` 記錄拆分。

### 3.6 兩台機器的切換步驟(寫進交付說明)

```bash
# 兩台各做一次
pipx uninstall ai-config 2>/dev/null; rm -f ~/.local/bin/ai-config  # 清舊安裝(含 ~/.venvs/ai-config)
pipx install git+https://github.com/CSL426/ai-config.git            # 或跑工具 repo 的 install.sh
cd ~/ai-config && git pull                                           # 資料 repo 瘦身版
ai-config status                                                     # 驗證
```

## 4. 執行順序

1. 先在資料 repo 把目前未提交的工作全部 commit + push(乾淨基線)。
2. 建工具 repo(先私有),搬檔 + §3.1 + §3.4,測試全綠。
3. §3.2 sanitize 掃描通過 → 轉 public → 驗證匿名 `pipx install git+...`。
4. 資料 repo 瘦身 PR(§3.5),兩台機器照 §3.6 切換並實測。
5. 全部驗收通過後,兩個 repo 各打 tag(工具 `v1.0.0`)。

## 5. 風險與對策

| 風險 | 對策 |
|------|------|
| sanitize 漏網導致個人資訊公開 | §3.2 grep 清單設為 CI 檢查;**public 切換是最後一步**,由使用者本人按下 |
| 兩台既有安裝指向舊佈局 | §3.6 清舊安裝步驟;工具找不到資料 repo 時的錯誤訊息已含解法 |
| 工具/資料版本漂移 | 資料 repo README 記錄「最低工具版本」;工具 breaking change 需在 CHANGELOG 標注 |
| 檔案同步軟體仍在搬 repo | 拆分前先把兩個 repo 都排除出檔案同步(既有未解問題,拆分會放大它) |

## 6. 驗收清單

- [ ] 工具 repo:CI 綠(ubuntu+windows × 3.11/3.12);sanitize grep 零命中;匿名 `pipx install git+https://github.com/CSL426/ai-config.git` 成功。
- [ ] 資料 repo:無任何程式檔;invariants 測試綠;README 兩行 bootstrap 正確。
- [ ] 兩台實機:切換後任意目錄 `ai-config status` 全綠、`apply` 冪等、`sync` 作用於資料 repo。
- [ ] 使用者確認後,本文件與 `python-cli-migration.md` 相應項目才標 Done。
