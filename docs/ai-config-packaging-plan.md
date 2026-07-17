# ai-config 可安裝 CLI(pipx)+ sync 子命令 實作規格

**狀態:Draft**
**建立日期:2026-07-17**
**執行者:交由任一 coding agent 實作;本文件自足,不需其他對話上下文。**

---

## 0. 背景(現況)

repo `~/ai-config` 是跨 AI CLI 的設定管理中樞,核心引擎已遷移為單一 Python package `ai_config/`(stdlib-only,Python 3.11+),由兩個薄 wrapper(`ai-config.sh` / `ai-config.ps1`)呼叫 `python -m ai_config`。指令:`init` / `apply` / `status` / `list` / `reset` / `project`。

使用者痛點:目前要嘛進 repo 跑 `./ai-config.sh`,要嘛手動建 symlink。**目標是像 npm -g / pipx 一樣「安裝後直接有全域 `ai-config` 指令」,Linux 與 Windows 皆然,不需要手動 symlink 或改 `$PROFILE`。**

關鍵既有事實(實作前必讀):

- `ai_config/paths.py` 的 `SCRIPT_DIR = Path(__file__).resolve().parents[1]` — **假設 package 與設定資料(`claude/`、`codex/`、`agy/`)同住一個 repo**。非 editable 安裝會把 package 複製進 site-packages,`SCRIPT_DIR` 會指錯。
- `paths.ENTRYPOINT` 在 **import 時**讀環境變數 `AI_CONFIG_ENTRYPOINT`(wrapper 會設;預設依平台為 `./ai-config.sh` 或 `.\ai-config.ps1`),用於 usage 與提示文字。
- 測試 harness:`tests/test_apply_projection.py` 的 `run_ai_config()` 依 `AI_CONFIG_IMPL`(`sh`|`py`)切換受測實作;`tests/test_wrappers.py` 斷言 wrapper 輸出含 `./ai-config.sh <command> [tool]`;`tests/test_windows_sync.py` 斷言 `.\ai-config.ps1 <command> [tool]`。**這些斷言不得破壞。**
- `ai-config.sh` 已支援「透過 PATH symlink 執行」(解析 symlink 找 repo),並有 regression 測試 `test_shell_wrapper_works_through_path_symlink`。
- 全套測試:`pytest tests/`(目前 120+ 條,兩種 IMPL 都必須全綠)。

## 1. 交付物 A:pipx 可安裝 package

### A1. `pyproject.toml`(repo 根目錄)

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "ai-config"
version = "1.0.0"
description = "Cross-AI tool configuration manager (Claude Code / Codex / Antigravity)"
requires-python = ">=3.11"

[project.scripts]
ai-config = "ai_config.cli:console_main"

[tool.setuptools]
packages = ["ai_config", "ai_config.tools"]
```

- **必須**明列 `packages`,避免 setuptools 自動探索把 repo 根目錄的非 package 目錄(`claude/`、`legacy/`、`tests/` 等)掃進去。
- 版本號從 1.0.0 起;之後手動維護。

### A2. 新模組 `ai_config/cli.py`

```python
import os


def console_main() -> int:
    # 必須在 import ai_config.__main__ 之前 setdefault:
    # paths.ENTRYPOINT 在模組 import 時就讀環境變數。
    os.environ.setdefault("AI_CONFIG_ENTRYPOINT", "ai-config")
    from ai_config.__main__ import main

    return main()
```

理由:console script 進來時沒有 wrapper 幫忙設 `AI_CONFIG_ENTRYPOINT`,提示文字應顯示 `ai-config` 而非 `./ai-config.sh`。因 `ENTRYPOINT` 是 import-time 常數,必須用延遲 import。

### A3. 資料 repo 定位(`ai_config/paths.py`)

`SCRIPT_DIR` 改為三段式解析:

1. 環境變數 `AI_CONFIG_REPO`(`expanduser().resolve()`)優先;
2. 否則維持現行 `Path(__file__).resolve().parents[1]`(editable 安裝與 wrapper 模式都正確);
3. 在 `main()` 入口(或 `console_main`)加健全性檢查:`SCRIPT_DIR / "claude"` 不是目錄時,`log_error` 明確訊息並 return 1,訊息需包含兩個解法:
   - `pipx install --editable <repo路徑>` 重裝,或
   - `export AI_CONFIG_REPO=<repo路徑>`(Windows:`setx AI_CONFIG_REPO ...`)。

**明確不支援**非 editable 且未設 `AI_CONFIG_REPO` 的安裝形態——設定資料活在 git repo 裡,這是刻意設計(repo 是 source of truth)。

### A4. 安裝方式(寫進 README「快速開始」)

```bash
# Linux
pipx install --editable ~/ai-config
```
```powershell
# Windows(pipx 會生成 ai-config.exe 到 PATH)
pipx install --editable "$HOME\ai-config"
```

- 沒有 pipx 的環境:`python3 -m pip install --user --editable ~/ai-config` 為替代方案,一併寫進 README。
- README 保留 wrapper 用法作為「免安裝模式」。
- **注意**:安裝後若 `~/.local/bin/ai-config` 已存在手動 symlink(目前 Linux 機器上有,指向 `ai-config.sh`),pipx 會拒絕或衝突——文件與實作都要處理:安裝步驟第一步先 `rm -f ~/.local/bin/ai-config`。

## 2. 交付物 B:`sync` 子命令

`ai-config sync [tool]`:

1. `git -C <SCRIPT_DIR> pull --rebase --autostash`(subprocess,繼承 stdout/stderr;git 不存在或非 git repo → `log_error` 並 return 1);
2. pull 成功後自動跑等同 `status [tool]` 的輸出;
3. 結尾 `log_info` 提示:`Run {ENTRYPOINT} apply to deploy`。**不自動 apply**(apply 是破壞性動作,留給使用者)。

- usage 文字加入 `sync` 一行:`sync [tool]    Pull latest repo changes, then show status`。
- pull 產生 conflict 時:git 自己的錯誤輸出直接透傳,return git 的非零 exit code,不要吞。

## 3. 測試要求

新增(至少):

1. `pyproject.toml` 存在且 `[project.scripts]` 指向 `ai_config.cli:console_main`(repository invariant 測試)。
2. `console_main` 在未設 `AI_CONFIG_ENTRYPOINT` 時,usage 輸出含 `ai-config <command> [tool]`(直接呼叫函式、capsys 斷言即可,不需真的 pipx install)。
3. `AI_CONFIG_REPO` 指向假 repo 時 `SCRIPT_DIR` 跟著走(subprocess 跑 `python -m ai_config list` 驗證)。
4. `SCRIPT_DIR` 無 `claude/` 目錄時,指令以非零退出並輸出含 `AI_CONFIG_REPO` 的錯誤訊息。
5. `sync`:在 tmp git repo(裸 remote + clone)場景下,remote 有新 commit → `sync` 後本地 HEAD 前進且輸出含 `Status:`;非 git 目錄 → 非零退出。

回歸:`pytest tests/` 全綠 ×(`AI_CONFIG_IMPL=sh` 與 `py` 兩輪);`bash -n ai-config.sh legacy/ai-config.sh legacy/scripts/*.sh`。

## 4. 文件更新

- `README.md`:快速開始改為「pipx 安裝」為主、wrapper 為輔;加 `sync` 說明與典型雙機工作流:
  `機器 A 改設定 → commit/push → 機器 B:ai-config sync → ai-config apply`。
- `CLAUDE.md`(repo 根):目錄地圖表格加 `pyproject.toml` 一行;「改 ai_config/** 後必跑測試」規則不變。
- `docs/python-cli-migration.md`:「遷移後另案」勾掉 packaging 與 sync 兩項(完成後)。
- `CHANGELOG.md`:新增條目。

## 5. 範圍外(不要做)

- 不發佈 PyPI;僅本機 editable 安裝。
- 不做自動 apply、不做背景 daemon、不碰檔案同步軟體整合。
- 不修改 `legacy/` 下任何檔案。
- 不引入任何第三方依賴(stdlib-only 不變)。

## 6. 驗收清單

- [x] Linux:安裝後任意目錄 `ai-config status` 正常、usage 顯示 `ai-config`(2026-07-17 實測)。
- [ ] Windows:同上(`ai-config.exe`),`.\ai-config.ps1` wrapper 仍可用。**尚未在 Windows 實機驗證,勿先勾。**
- [ ] `ai-config sync` 在雙機工作流實測通過。**測試有 tmp git repo 模擬,但雙機實測要等 push + Windows pull 後。**
- [x] 兩種 `AI_CONFIG_IMPL` 下 `pytest tests/` 全綠(125 passed, 1 skipped);新測試 5 條(test_packaging_and_sync.py)。
- [x] README / CLAUDE.md / CHANGELOG / migration 文件已更新。
