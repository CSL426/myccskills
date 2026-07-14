# claude/shared — 跨工具共享 skill 來源

放「想分享給 agy / codex,但 Claude 本身不裝成 skill」的 skill。
這些是 git 追蹤的權威來源,apply/project 時投射到對應工具的 `skills/`。

## 結構

```
claude/shared/
├── both/   # 同步到 agy + codex
├── agy/    # 只進 agy (Antigravity CLI)
└── codex/  # 只進 codex
```

每個 skill 一個子目錄,內含 `SKILL.md`(+ 選配 `references/` `examples/` `scripts/` `agents/`)。

## 為什麼存在

Claude 的內建 slash command(`/simplify` 等)與 plugin 不是可同步的檔案,
但有些 skill 你想手動鏡像分享給其他 CLI。放這裡即可:
改了就同步,來源刪了就被受管清單機制自動清掉(不再變孤兒)。

## 注意

來源固定取自 repo 的 `claude/shared/`,不受 `project`(live `~/.claude/`)模式影響。
