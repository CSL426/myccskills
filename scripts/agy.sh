#!/usr/bin/env bash
# Antigravity CLI (~/.gemini/antigravity-cli/): init, apply helpers
# Shared content is projected from claude/ — init remains a no-op for shared files.

stage_agy_projection() {
    local dst="$1"
    local src="$SCRIPT_DIR/agy"
    local mcp_source

    mkdir -p "$dst"

    mcp_source="$(first_existing_file "$src/mcp_config.json" "$CLAUDE_SOURCE_DIR/mcp.json" || true)"
    if [[ -n "$mcp_source" ]]; then
        copy_file_to_stage "$mcp_source" "$dst/mcp_config.json"
    fi

    # settings.json (unique to agy)
    copy_file_to_stage "$src/settings.json" "$dst/settings.json"

    project_agents_to_skills "$CLAUDE_SOURCE_DIR/agents" "$dst/skills"
    if [[ -d "$src/skills" ]]; then
        sync_skills "$src/skills" "$dst/skills"
    fi

    # Sync live installed skills from Claude if available (during project)
    if [[ -d "$CLAUDE_SOURCE_DIR/skills" ]]; then
        sync_skills "$CLAUDE_SOURCE_DIR/skills" "$dst/skills"
    fi

    # Shared skills (claude/shared/{both,agy}) — always from repo, never live
    sync_shared_skills agy "$dst/skills"

    # Sync live installed plugins from Claude if available (during project)
    if [[ -d "$CLAUDE_SOURCE_DIR/plugins" ]]; then
        mkdir -p "$dst/plugins"
        rsync -a --delete "$CLAUDE_SOURCE_DIR/plugins/" "$dst/plugins/"
        # Fix paths in installed_plugins.json to match agy's home
        if [[ -f "$dst/plugins/installed_plugins.json" ]]; then
            sed -i "s|/home/human/\.claude/plugins|/home/human/\.gemini/antigravity-cli/plugins|g" "$dst/plugins/installed_plugins.json"
        fi
    fi

    return 0
}

init_agy() {
    log_header "Init Antigravity CLI"
    local src="$AGY_HOME"
    local dst="$SCRIPT_DIR/agy"

    if [[ ! -d "$src" ]]; then
        log_warn "Antigravity CLI directory not found: $src"
        return 0
    fi

    # settings.json — Antigravity CLI-specific
    if [[ -f "$src/settings.json" ]]; then
        safe_cp "$src/settings.json" "$dst/settings.json"
        log_success "settings.json"
    fi

    # All other managed files (mcp_config.json, skills/) are projected from claude/ during apply
    log_info "All other files are projected from claude/ during apply — nothing else to init"
    log_success "Antigravity CLI init complete"
}

apply_agy_internal() {
    local src="$1" dst="$2"

    # mcp_config.json (projected from claude/mcp.json if no agy/mcp_config.json)
    if [[ -f "$src/mcp_config.json" ]]; then
        cp -L "$src/mcp_config.json" "$dst/mcp_config.json"
        log_success "mcp_config.json"
    fi

    # settings.json
    if [[ -f "$src/settings.json" ]]; then
        safe_cp "$src/settings.json" "$dst/settings.json"
        log_success "settings.json"
    fi

    # Ensure skills symlink exists before writing through it.
    ensure_agy_shared_links

    # skills/ (projected from claude/agents/ + agy/skills/ + shared/ during staging)
    if [[ -d "$src/skills" ]]; then
        sync_skills "$src/skills" "$dst/skills"
        reconcile_managed_skills "$src/skills" "$dst/skills"
        log_success "skills/"
    fi

    # plugins/
    if [[ -d "$src/plugins" ]]; then
        mkdir -p "$dst/plugins"
        rsync -a --delete "$src/plugins/" "$dst/plugins/"
        log_success "plugins/"
    fi
}

apply_agy() {
    log_header "Apply Antigravity CLI"
    run_apply_tool "agy"
}
