#!/usr/bin/env bash
# ai-config bootstrap installer (Linux / Unix)
#
#   全新機器:  git clone <repo-url> ~/ai-config && ~/ai-config/install.sh
#   已有 repo: ~/ai-config/install.sh
#
# 全自動處理:定位系統 Python → 建獨立 venv → editable 安裝 → PATH shim。
# 可用環境變數覆寫:AI_CONFIG_REPO_URL / AI_CONFIG_HOME / AI_CONFIG_VENV
set -euo pipefail

REPO_URL="${AI_CONFIG_REPO_URL:-git@github.com:CSL426/myccskills.git}"
TARGET="${AI_CONFIG_HOME:-$HOME/ai-config}"
VENV="${AI_CONFIG_VENV:-$HOME/.venvs/ai-config}"
BIN_DIR="$HOME/.local/bin"

step() { printf '\033[0;36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Running from inside a checkout? Then that checkout is the target.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/pyproject.toml" && -d "$script_dir/ai_config" ]]; then
    TARGET="$script_dir"
    step "Using this checkout: $TARGET"
elif [[ -d "$TARGET/.git" ]]; then
    step "Using existing checkout: $TARGET"
else
    command -v git >/dev/null 2>&1 || fail "git is required"
    step "Cloning $REPO_URL → $TARGET"
    git clone "$REPO_URL" "$TARGET"
fi

# System Python ≥ 3.11 (prefer /usr/bin/python3 so the venv never depends on
# pyenv/conda interpreters that may be switched or removed later).
PY=""
for candidate in /usr/bin/python3 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
        && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))' 2>/dev/null
    then
        PY="$(command -v "$candidate")"
        break
    fi
done
[[ -n "$PY" ]] || fail "Python 3.11+ not found"
step "Python: $PY"

step "Creating venv: $VENV"
"$PY" -m venv "$VENV"
"$VENV/bin/pip" install --quiet --editable "$TARGET"

mkdir -p "$BIN_DIR"
ln -sf "$VENV/bin/ai-config" "$BIN_DIR/ai-config"
step "Installed shim: $BIN_DIR/ai-config"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH — add to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

step "Done. Try: ai-config status"
