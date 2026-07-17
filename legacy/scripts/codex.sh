#!/usr/bin/env bash
# Codex CLI: init, apply helpers
# Only manages Codex-specific files; shared content is projected from claude/.

# Filter config.toml: remove [projects.*] blocks
filter_codex_config() {
    local input="$1"
    awk '
        /^\[projects\./ { skip=1; next }
        /^\[/ { skip=0 }
        !skip { print }
    ' "$input" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# Merge config.toml: replace general settings, keep target [projects.*] blocks
merge_codex_config() {
    local source_config="$1"
    local target_config="$2"

    # Collect ONLY [projects.*] tables from the target so user trust settings
    # survive. Start with in_projects=0 so top-level keys (model, etc.) before
    # the first table are NOT captured (that caused duplicate-key corruption).
    local projects_block
    projects_block="$(awk '
        /^\[projects\./   { in_projects=1; print; next }
        /^\[/             { in_projects=0; next }
        in_projects       { print }
    ' "$target_config" 2>/dev/null || true)"

    local result
    result="$(cat "$source_config")"

    if [[ -n "$projects_block" ]]; then
        result="$result"$'\n'"$projects_block"
    fi

    echo "$result"
}

stage_codex_projection() {
    local dst="$1"
    local src="$SCRIPT_DIR/codex"
    local instruction_source

    mkdir -p "$dst"

    instruction_source="$(first_existing_file "$src/AGENTS.md" "$CLAUDE_SOURCE_DIR/CLAUDE.md" || true)"
    if [[ -n "$instruction_source" ]]; then
        copy_file_to_stage "$instruction_source" "$dst/AGENTS.md"
    fi

    copy_file_to_stage "$src/config.toml" "$dst/config.toml"
    overlay_dir_to_stage "$CLAUDE_SOURCE_DIR/rules" "$dst/rules"
    overlay_dir_to_stage "$src/rules" "$dst/rules"
    project_agents_to_skills "$CLAUDE_SOURCE_DIR/agents" "$dst/skills"
    if [[ -d "$src/skills" ]]; then
        sync_skills "$src/skills" "$dst/skills"
    fi
    if [[ -d "$CLAUDE_SOURCE_DIR/skills" ]]; then
        sync_skills "$CLAUDE_SOURCE_DIR/skills" "$dst/skills"
    fi
    sync_shared_skills codex "$dst/skills"
    return 0
}

init_codex() {
    log_header "Init Codex"
    local src="$CODEX_HOME"
    local dst="$SCRIPT_DIR/codex"

    if [[ ! -d "$src" ]]; then
        log_error "Codex config directory not found: $src"
        return 1
    fi

    # config.toml — Codex-specific (no Claude equivalent)
    if [[ -f "$src/config.toml" ]]; then
        mkdir -p "$dst"
        filter_codex_config "$src/config.toml" > "$dst/config.toml"
        log_success "config.toml (filtered, no [projects.*])"
    fi

    # Skip AGENTS.md, rules/, skills/ — projected from claude/ during apply
    log_info "Skipping shared files (projected from claude/ during apply)"

    log_success "Codex init complete"
}

apply_codex_internal() {
    local src="$1" dst="$2"

    # AGENTS.md (projected from claude/CLAUDE.md if no codex/AGENTS.md)
    if [[ -f "$src/AGENTS.md" ]]; then
        cp -L "$src/AGENTS.md" "$dst/AGENTS.md"
        log_success "AGENTS.md"
    fi

    # config.toml (merge: replace general, keep target [projects.*])
    if [[ -f "$src/config.toml" ]]; then
        mkdir -p "$dst"
        if [[ -f "$dst/config.toml" ]]; then
            merge_codex_config "$src/config.toml" "$dst/config.toml" > "$dst/config.toml.tmp"
            mv "$dst/config.toml.tmp" "$dst/config.toml"
            log_success "config.toml (merged, preserved [projects.*])"
        else
            cp "$src/config.toml" "$dst/config.toml"
            log_success "config.toml (fresh copy)"
        fi
    fi

    # rules/ (merged from claude/rules/ + codex/rules/ during staging)
    if [[ -d "$src/rules" ]]; then
        mkdir -p "$dst/rules"
        rsync -aL "$src/rules/" "$dst/rules/"
        log_success "rules/"
    fi

    # skills/ (projected from claude/agents/ + codex/skills/ + shared/ during staging)
    if [[ -d "$src/skills" ]]; then
        sync_skills "$src/skills" "$dst/skills"
        reconcile_managed_skills "$src/skills" "$dst/skills"
        log_success "skills/"
    fi
}

apply_codex() {
    log_header "Apply Codex"
    run_apply_tool "codex"
    ensure_codex_shared_links
}
