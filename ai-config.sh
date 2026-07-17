#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON=()
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
        && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'
    then
        PYTHON=("$candidate")
        break
    fi
done
if [[ ${#PYTHON[@]} -eq 0 ]] && command -v py >/dev/null 2>&1 \
    && py -3 -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'
then
    PYTHON=(py -3)
fi

if [[ ${#PYTHON[@]} -eq 0 ]]; then
    echo "✗ ai-config requires Python 3.11 or newer." >&2
    exit 1
fi

export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"
export AI_CONFIG_ENTRYPOINT="./ai-config.sh"
exec "${PYTHON[@]}" -m ai_config "$@"
