#!/usr/bin/env bash
# Claude Code: init, apply helpers
# Claude is the source of truth — init syncs everything, including deletions.

CLAUDE_MANAGED_FILES=(CLAUDE.md mcp.json settings.json statusline.sh)
CLAUDE_MANAGED_DIRS=(rules agents commands)

stage_claude_projection() {
    local dst="$1"
    local src="$CLAUDE_SOURCE_DIR"

    mkdir -p "$dst"

    local f d
    for f in "${CLAUDE_MANAGED_FILES[@]}"; do
        copy_file_to_stage "$src/$f" "$dst/$f"
    done

    for d in "${CLAUDE_MANAGED_DIRS[@]}"; do
        overlay_dir_to_stage "$src/$d" "$dst/$d"
    done
    return 0
}

init_claude() {
    log_header "Init Claude"
    local src="$CLAUDE_HOME"
    local dst="$SCRIPT_DIR/claude"

    if [[ ! -d "$src" ]]; then
        log_error "Claude config directory not found: $src"
        return 1
    fi

    # Sync single files — copy if exists in source, remove from repo if not
    for f in "${CLAUDE_MANAGED_FILES[@]}"; do
        if [[ -f "$src/$f" ]]; then
            safe_cp "$src/$f" "$dst/$f"
            log_success "$f"
        elif [[ -f "$dst/$f" ]]; then
            rm "$dst/$f"
            log_info "$f removed (no longer in $src)"
        fi
    done

    # Sync directories — --delete ensures repo matches source
    for d in "${CLAUDE_MANAGED_DIRS[@]}"; do
        if [[ -d "$src/$d" ]]; then
            safe_rsync "$src/$d/" "$dst/$d/"
            log_success "$d/"
        elif [[ -d "$dst/$d" ]]; then
            rm -rf "$dst/$d"
            log_info "$d/ removed (no longer in $src)"
        fi
    done

    log_success "Claude init complete"
}

apply_claude_internal() {
    local src="$1" dst="$2"

    for f in "${CLAUDE_MANAGED_FILES[@]}"; do
        if [[ -f "$src/$f" ]]; then
            safe_cp "$src/$f" "$dst/$f"
            log_success "$f"
        fi
    done

    for d in "${CLAUDE_MANAGED_DIRS[@]}"; do
        if [[ -d "$src/$d" ]]; then
            safe_rsync "$src/$d/" "$dst/$d/"
            log_success "$d/"
        fi
    done
}

apply_claude() {
    log_header "Apply Claude"
    run_apply_tool "claude"
}
