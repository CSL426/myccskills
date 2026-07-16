#!/usr/bin/env bash
set -euo pipefail

# ai-config: Cross-AI tool configuration management CLI
# Manages portable config files for Claude Code, Codex, Antigravity CLI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_BASE="$HOME/.ai-config-backup"

# Source directory for Claude config (used in projections; can be overridden by 'project' command)
CLAUDE_SOURCE_DIR="$SCRIPT_DIR/claude"

# Tool home directories
CLAUDE_HOME="$HOME/.claude"
CODEX_HOME="$HOME/.codex"
AGY_HOME="$HOME/.gemini/antigravity-cli"

# Codex runtime homes keep separate auth/session DB state, but should share
# managed config files from ~/.codex.
CODEX_SHARED_HOMES=("$HOME/.codex-csl" "$HOME/.codex-set")
CODEX_SHARED_PATHS=(AGENTS.md config.toml rules skills plugins prompts)
# agy: AGY_HOME/skills is a symlink into this canonical store so multiple agy
# surfaces share one skills dir (mirrors the codex multi-home pattern).
AGY_CANONICAL_SKILLS="$HOME/.gemini/antigravity/skills"

# All managed tools (order matters for init/apply/status)
ALL_TOOLS=(claude codex agy)

# Credential files to never copy
EXCLUDED_FILES=(".credentials.json" "auth.json" "oauth_creds.json" "google_accounts.json" "trustedFolders.json")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─── Shared helpers ───────────────────────────────────────────

log_info()    { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
log_error()   { echo -e "${RED}✗${NC} $*" >&2; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

is_excluded() {
    local filename
    filename="$(basename "$1")"
    local excl_pattern
    excl_pattern="^($(IFS='|'; echo "${EXCLUDED_FILES[*]}"))$"
    [[ "$filename" =~ $excl_pattern ]]
}

safe_cp() {
    local src="$1" dst="$2"
    if is_excluded "$src"; then
        log_warn "Skipping credential file: $(basename "$src")"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

safe_rsync() {
    local src="$1" dst="$2"
    local exclude_args=()
    for excl in "${EXCLUDED_FILES[@]}"; do
        exclude_args+=(--exclude "$excl")
    done
    mkdir -p "$dst"
    rsync -a --delete "${exclude_args[@]}" "$src" "$dst"
}

dir_has_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -type f -print -quit | grep -q .
}

copy_file_to_stage() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
}

overlay_dir_to_stage() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    rsync -aL "$src/" "$dst/"
}

first_existing_file() {
    local path
    for path in "$@"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

sanitize_skill_frontmatter() {
    # Normalizes a SKILL.md / agent.md so strict parsers (Codex, Antigravity) accept it:
    # 1. If no YAML frontmatter, inject a minimal one (name from first heading).
    # 2. If frontmatter lacks `description`, synthesize one from name/heading.
    # 3. Rewrite description as a block scalar (>-) so embedded colons/quotes are safe.
    # 4. Inject `metadata.short-description` (first sentence of description) if absent —
    #    Codex requires it; harmless extra field for parsers that ignore it.
    local content
    content="$(cat)"

    # Check if file starts with ---
    # NOTE: plain bash checks, no pipelines — `grep -q`/`awk ... exit` close the
    # pipe early and SIGPIPE the echo on >64KB files, which pipefail+set -e
    # turns into a silent 141 death (bit us via hallmark's 67KB SKILL.md).
    if [[ "$content" != ---* ]]; then
        # Derive skill name from first # heading, falling back to "skill"
        local skill_name
        skill_name="$(echo "$content" | awk '/^# / && !found { sub(/^# /, ""); print; found=1 }')"
        skill_name="${skill_name:-skill}"
        # Prepend minimal frontmatter
        content="$(printf -- '---\nname: %s\n---\n' "$skill_name")"$'\n'"$content"
    fi

    echo "$content" | awk '
        function first_sentence(s,   p) {
            # up to first period or the whole string; trim
            p = index(s, ". ")
            if (p > 0) s = substr(s, 1, p - 1)
            sub(/\.$/, "", s)
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }

        BEGIN { in_front=0; done=0 }

        # Opening fence
        /^---$/ && !in_front && !done {
            in_front=1
            # buffer frontmatter lines so we can append missing fields before closing
            fm_n=0
            has_desc=0; has_meta=0; has_short=0; name_val=""; desc_val=""
            print
            next
        }

        # Closing fence: flush synthesized fields, then close
        /^---$/ && in_front {
            if (!has_desc) {
                desc_val = (name_val != "" ? name_val : "skill")
                print "description: >-"
                print "  " desc_val
            }
            if (!has_short) {
                short = first_sentence(desc_val != "" ? desc_val : (name_val != "" ? name_val : "skill"))
                if (has_meta) {
                    # metadata: block exists but no short-description — append nested
                    print "  short-description: " short
                } else {
                    print "metadata:"
                    print "  short-description: " short
                }
            }
            in_front=0; done=1
            print
            next
        }

        in_front {
            if ($0 ~ /^name:/) { name_val = substr($0, index($0, ":") + 2); gsub(/^[ \t]+|[ \t]+$/, "", name_val) }
            if ($0 ~ /^metadata:/) { has_meta=1 }
            if ($0 ~ /^[ \t]+short-description:/) { has_short=1 }
            if ($0 ~ /^description:/) {
                has_desc=1
                val = substr($0, index($0, ":") + 2)
                desc_val = val
                gsub(/^[ \t]+|[ \t]+$/, "", desc_val)
                if (val ~ /^[|>'"'"'"]/) { print; next }
                print "description: >-"
                print "  " val
                next
            }
            print
            next
        }

        { print }
    '
}

project_agents_to_skills() {
    local agents_dir="$1" dst_skills="$2"
    [[ -d "$agents_dir" ]] || return 0

    mkdir -p "$dst_skills"
    for agent_file in "$agents_dir"/*.md; do
        if [[ ! -f "$agent_file" ]]; then continue; fi

        local agent_name dst_skill
        agent_name="$(basename "$agent_file" .md)"
        dst_skill="$dst_skills/$agent_name"
        mkdir -p "$dst_skill"
        sanitize_skill_frontmatter < "$agent_file" > "$dst_skill/SKILL.md"
    done
}

# Backup covers ONLY the paths apply can modify. Runtime data (plugin caches,
# session transcripts, browser recordings) is never touched by apply, so
# backing it up bloated ~/.ai-config-backup into the tens of GB.
CLAUDE_BACKUP_PATHS=(CLAUDE.md mcp.json settings.json rules agents commands)
CODEX_BACKUP_PATHS=(AGENTS.md config.toml rules skills)
AGY_BACKUP_PATHS=(mcp_config.json settings.json skills plugins)
BACKUP_KEEP=5

backup_paths_for() {
    case "$1" in
        claude) printf '%s\n' "${CLAUDE_BACKUP_PATHS[@]}" ;;
        codex)  printf '%s\n' "${CODEX_BACKUP_PATHS[@]}" ;;
        agy)    printf '%s\n' "${AGY_BACKUP_PATHS[@]}" ;;
    esac
}

prune_backups() {
    [[ -d "$BACKUP_BASE" ]] || return 0
    local old_snapshots
    old_snapshots="$(ls -1 "$BACKUP_BASE" 2>/dev/null | sort | head -n -"$BACKUP_KEEP")"
    [[ -n "$old_snapshots" ]] || return 0
    local snap
    while IFS= read -r snap; do
        rm -rf "${BACKUP_BASE:?}/${snap:?}"
    done <<< "$old_snapshots"
    log_info "Pruned old backups (kept newest $BACKUP_KEEP)"
}

create_backup() {
    local tool="$1" source_dir="$2"
    local timestamp backup_dir
    timestamp="$(date +%Y-%m-%d-%H%M%S)"
    backup_dir="$BACKUP_BASE/$timestamp/$tool"

    if [[ ! -d "$source_dir" ]]; then return 0; fi

    mkdir -p "$backup_dir"
    local path
    while IFS= read -r path; do
        [[ -n "$path" && -e "$source_dir/$path" ]] || continue
        # -L: agy skills/ is a symlink into ~/.gemini/antigravity/skills;
        # back up the real content, not the link.
        rsync -aL "$source_dir/$path" "$backup_dir/"
    done < <(backup_paths_for "$tool")
    log_info "Backed up managed files: $source_dir → $backup_dir"
    prune_backups
}

# Sync skills: copy SKILL.md + examples/ + references/ per skill
sync_skills() {
    local src_skills="$1" dst_skills="$2"
    mkdir -p "$dst_skills"
    for skill_dir in "$src_skills"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        [[ "$skill_name" == .* ]] && continue

        local dst_skill="$dst_skills/$skill_name"
        mkdir -p "$dst_skill"

        # Guard with if (not `[[ ]] &&`): a trailing false condition would
        # propagate as a nonzero return and kill set -e callers (e.g. status).
        if [[ -f "$skill_dir/SKILL.md" ]]; then
            sanitize_skill_frontmatter < "$skill_dir/SKILL.md" > "$dst_skill/SKILL.md"
        fi
        if [[ -d "$skill_dir/examples" ]]; then
            safe_rsync "$skill_dir/examples/" "$dst_skill/examples/"
        fi
        if [[ -d "$skill_dir/references" ]]; then
            safe_rsync "$skill_dir/references/" "$dst_skill/references/"
        fi
    done
    return 0
}

# Project shared skills (claude/shared/{both,<tool>}) into a tool's skills dir.
# Source is ALWAYS the repo (claude/shared/), never live ~/.claude/ — so it works
# identically in both apply and project(live) modes.
sync_shared_skills() {
    local tool="$1" dst_skills="$2"
    local shared_root="$SCRIPT_DIR/claude/shared"
    [[ -d "$shared_root/both" ]] && sync_skills "$shared_root/both" "$dst_skills"
    [[ -d "$shared_root/$tool" ]] && sync_skills "$shared_root/$tool" "$dst_skills"
    return 0
}

# Reconcile a tool's skills dir against the names we wrote this run.
# Deletes skills that WE managed previously but are no longer in the source
# (orphan cleanup), while leaving hand-installed skills untouched.
#
#   $1 = staged skills dir (authoritative list of what should exist)
#   $2 = destination skills dir (already synced; gets the manifest + pruning)
#
# Manifest: <dst>/.ai-config-managed — newline-delimited skill names we own.
MANIFEST_NAME=".ai-config-managed"
reconcile_managed_skills() {
    local staged_skills="$1" dst_skills="$2"
    [[ -d "$dst_skills" ]] || return 0

    local manifest="$dst_skills/$MANIFEST_NAME"

    # Current names = subdirs present in the staged projection.
    local current
    current="$(find "$staged_skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)"

    # Prune: names in old manifest but NOT in current staged set.
    if [[ -f "$manifest" ]]; then
        local name
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            if ! grep -qxF "$name" <<<"$current"; then
                if [[ -d "$dst_skills/$name" ]]; then
                    rm -rf "${dst_skills:?}/$name"
                    log_info "pruned orphan skill: $name"
                fi
            fi
        done < "$manifest"
    fi

    # Write fresh manifest (only what we now own).
    printf '%s\n' "$current" > "$manifest"
}

count_files() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -type f ! -name '.*' | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Resolve tool home directory by name
tool_home() {
    case "$1" in
        claude)          echo "$CLAUDE_HOME" ;;
        codex)           echo "$CODEX_HOME" ;;
        agy)             echo "$AGY_HOME" ;;
    esac
}

ensure_codex_shared_links() {
    local shared_home rel_path src dst

    for shared_home in "${CODEX_SHARED_HOMES[@]}"; do
        [[ "$shared_home" == "$CODEX_HOME" ]] && continue
        [[ -d "$shared_home" ]] || continue

        for rel_path in "${CODEX_SHARED_PATHS[@]}"; do
            src="$CODEX_HOME/$rel_path"
            dst="$shared_home/$rel_path"
            [[ -e "$src" || -L "$src" ]] || continue

            if [[ -L "$dst" ]]; then
                if [[ "$(readlink "$dst")" == "$src" ]]; then
                    continue
                fi
                log_warn "Not replacing existing symlink: $dst -> $(readlink "$dst")"
                continue
            fi

            if [[ -e "$dst" ]]; then
                log_warn "Not replacing existing Codex path: $dst"
                continue
            fi

            ln -s "$src" "$dst"
            log_success "linked ${shared_home/#$HOME/~}/$rel_path -> ~/.codex/$rel_path"
        done
    done
}

# Ensure AGY_HOME/skills is a symlink to the canonical skills store, so the
# skills dir survives Antigravity CLI reinstalls and stays shared. Mirrors the
# protection logic in ensure_codex_shared_links (never clobber a real dir).
ensure_agy_shared_links() {
    local link="$AGY_HOME/skills"
    local target="$AGY_CANONICAL_SKILLS"

    mkdir -p "$target"

    if [[ -L "$link" ]]; then
        if [[ "$(readlink "$link")" == "$target" ]]; then
            return 0
        fi
        log_warn "Not replacing existing symlink: $link -> $(readlink "$link")"
        return 0
    fi

    if [[ -e "$link" ]]; then
        log_warn "Not replacing existing agy skills dir: $link (expected symlink -> $target)"
        return 0
    fi

    mkdir -p "$AGY_HOME"
    ln -s "$target" "$link"
    log_success "linked ~/.gemini/antigravity-cli/skills -> ~/.gemini/antigravity/skills"
}

# Generic apply workflow: handles staging, checking, backup, and cleanup
run_apply_tool() {
    local tool="$1"
    local stage_fn="stage_${tool}_projection"
    local apply_fn="apply_${tool}_internal"
    local home_dir
    local stage_dir

    home_dir="$(tool_home "$tool")"
    stage_dir="$(mktemp -d)"

    if ! "$stage_fn" "$stage_dir"; then
        log_error "Failed to stage $tool projection"
        rm -rf "$stage_dir"
        return 1
    fi

    if ! dir_has_files "$stage_dir"; then
        log_error "No $tool config in ai-config/"
        rm -rf "$stage_dir"
        return 1
    fi

    create_backup "$tool" "$home_dir"
    mkdir -p "$home_dir"

    if ! "$apply_fn" "$stage_dir" "$home_dir"; then
        log_error "Failed to apply $tool config"
        rm -rf "$stage_dir"
        return 1
    fi

    rm -rf "$stage_dir"
}

# ─── Source tool scripts ──────────────────────────────────────

for _script in "$SCRIPT_DIR"/scripts/*.sh; do
    if [[ -f "$_script" ]]; then source "$_script"; fi
done

# ─── STATUS ───────────────────────────────────────────────────

stage_tool_projection() {
    local tool="$1" stage_dir="$2"
    "stage_${tool}_projection" "$stage_dir"
}

status_tool() {
    local tool="$1"
    local ai_dir
    local home_dir
    local stage_dir
    home_dir="$(tool_home "$tool")"
    stage_dir="$(mktemp -d)"
    ai_dir="$stage_dir"
    stage_tool_projection "$tool" "$stage_dir"

    log_header "Status: $tool"

    if ! dir_has_files "$ai_dir"; then
        log_warn "No config in ai-config/$tool/"
        rm -rf "$stage_dir"
        return 0
    fi
    if [[ ! -d "$home_dir" ]]; then
        log_warn "Tool home directory not found: $home_dir"
        rm -rf "$stage_dir"
        return 0
    fi

    local has_diff=false

    while IFS= read -r -d '' rel_path; do
        local ai_file="$ai_dir/$rel_path"
        local home_file="$home_dir/$rel_path"

        is_excluded "$rel_path" && continue

        if [[ ! -f "$home_file" ]]; then
            echo -e "  ${GREEN}+ $rel_path${NC} (only in ai-config)"
            has_diff=true
        elif ! diff -q "$ai_file" "$home_file" &>/dev/null; then
            # Special filtered comparisons
            if [[ "$tool" == "codex" && "$rel_path" == "config.toml" ]]; then
                local filtered
                filtered="$(filter_codex_config "$home_file")"
                if ! diff -q "$ai_file" <(echo "$filtered") &>/dev/null; then
                    echo -e "  ${YELLOW}~ $rel_path${NC} (differs, general settings only)"
                    diff --color=always "$ai_file" <(echo "$filtered") | head -20 || true
                    has_diff=true
                fi
            else
                echo -e "  ${YELLOW}~ $rel_path${NC}"
                diff --color=always "$ai_file" "$home_file" | head -20 || true
                has_diff=true
            fi
        fi
    done < <(cd "$ai_dir" && find . -type f -print0 | sed -z 's|^\./||')

    if [[ "$has_diff" == false ]]; then
        log_success "No differences found"
    fi

    rm -rf "$stage_dir"
}

# ─── SHARED MIRROR DRIFT ──────────────────────────────────────

# Shared skills under claude/shared/ that mirror an external source file can
# declare it in frontmatter:
#   metadata:
#     mirror-of: ~/.claude/commands/commit.md
#     mirror-hash: <sha256 of the source at copy time>
# status re-hashes each source and warns when the mirror is stale, so manual
# copies don't silently drift. Refresh = re-copy content + update mirror-hash.
check_shared_mirrors() {
    local shared_root="$SCRIPT_DIR/claude/shared"
    [[ -d "$shared_root" ]] || return 0

    local skill_md src_path src_hash cur_hash rel
    local checked=0 stale=0

    while IFS= read -r skill_md; do
        src_path="$(awk '/^[ \t]+mirror-of:/ { sub(/^[ \t]+mirror-of:[ \t]*/, ""); print; exit }' "$skill_md")"
        [[ -n "$src_path" ]] || continue
        src_hash="$(awk '/^[ \t]+mirror-hash:/ { sub(/^[ \t]+mirror-hash:[ \t]*/, ""); print; exit }' "$skill_md")"

        checked=$((checked + 1))
        rel="${skill_md#"$shared_root"/}"
        src_path="${src_path/#\~/$HOME}"

        if [[ ! -f "$src_path" ]]; then
            log_warn "mirror source missing: $rel ← ${src_path/#"$HOME"/\~}"
            stale=$((stale + 1))
            continue
        fi

        cur_hash="$(sha256sum "$src_path" | cut -d' ' -f1)"
        if [[ "$cur_hash" != "$src_hash" ]]; then
            log_warn "mirror stale: $rel — source changed: ${src_path/#"$HOME"/\~}"
            echo -e "    update the copy, then set ${CYAN}mirror-hash: $cur_hash${NC}"
            stale=$((stale + 1))
        fi
    done < <(find "$shared_root" -mindepth 3 -maxdepth 3 -name SKILL.md -type f 2>/dev/null | sort)

    if [[ "$checked" -gt 0 && "$stale" -eq 0 ]]; then
        log_success "All $checked mirrored shared skills up to date"
    fi
    return 0
}

# ─── PLUGIN DRIFT ─────────────────────────────────────────────

# Plugins live in each CLI's own registry/cache, outside file sync. The repo
# still records intent: claude/settings.json enabledPlugins (a listed key —
# true OR false — means the plugin is deliberately kept) and codex/config.toml
# [plugins.*] blocks. A plugin present in a live registry but absent from the
# repo's intent was removed on the Claude side and lingers elsewhere (how
# superpowers survived in agy). status warns; removal stays manual for agy,
# while codex heals on the next apply (merge drops live-only plugin blocks).
check_plugin_drift() {
    local drift=0 key

    local claude_settings="$CLAUDE_SOURCE_DIR/settings.json"
    local claude_keys=""
    if [[ -f "$claude_settings" ]]; then
        # enabledPlugins entries are the only "name@marketplace": true/false
        # pairs in settings.json, so match the shape instead of tracking braces.
        claude_keys="$(grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*\(true\|false\)' "$claude_settings" | sed 's/^"//; s/".*//' || true)"
    fi

    local agy_registry="$AGY_HOME/plugins/installed_plugins.json"
    if [[ -f "$agy_registry" && -n "$claude_keys" ]]; then
        local agy_keys
        agy_keys="$(grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*\[' "$agy_registry" | sed 's/^"//; s/".*//' || true)"
        while IFS= read -r key; do
            [[ -n "$key" ]] || continue
            if ! grep -Fxq "$key" <<< "$claude_keys"; then
                log_warn "agy has plugin not tracked in claude/settings.json: $key"
                echo -e "    remove with: ${CYAN}agy plugin uninstall $key${NC}"
                drift=$((drift + 1))
            fi
        done <<< "$agy_keys"
    fi

    local repo_codex="$SCRIPT_DIR/codex/config.toml"
    local live_codex="$CODEX_HOME/config.toml"
    if [[ -f "$repo_codex" && -f "$live_codex" ]]; then
        local repo_codex_keys live_codex_keys
        repo_codex_keys="$(grep -o '^\[plugins\."[^"]*"\]' "$repo_codex" | sed 's/^\[plugins\."//; s/"\]$//' || true)"
        live_codex_keys="$(grep -o '^\[plugins\."[^"]*"\]' "$live_codex" | sed 's/^\[plugins\."//; s/"\]$//' || true)"
        while IFS= read -r key; do
            [[ -n "$key" ]] || continue
            if ! grep -Fxq "$key" <<< "$repo_codex_keys"; then
                log_warn "codex live config has plugin not in repo codex/config.toml: $key"
                echo -e "    next ${CYAN}apply${NC} removes the config block; also run ${CYAN}codex${NC} plugin uninstall if installed"
                drift=$((drift + 1))
            fi
        done <<< "$live_codex_keys"
    fi

    if [[ "$drift" -eq 0 ]]; then
        log_success "No plugin drift detected"
    fi
    return 0
}

# ─── LIST ─────────────────────────────────────────────────────

do_list() {
    log_header "Managed AI Tool Configs"
    echo ""

    for tool_dir in "$SCRIPT_DIR"/*/; do
        if [[ ! -d "$tool_dir" ]]; then continue; fi
        local tool_name
        tool_name="$(basename "$tool_dir")"
        # Skip non-tool directories
        if [[ "$tool_name" == "scripts" ]]; then continue; fi

        local file_count
        file_count="$(count_files "$tool_dir")"

        if [[ "$file_count" -gt 0 ]]; then
            echo -e "  ${GREEN}●${NC} ${BOLD}$tool_name${NC}  ($file_count files)"
        else
            echo -e "  ${YELLOW}○${NC} ${tool_name}  (empty — run ${CYAN}init${NC} to populate)"
        fi
    done

    echo ""

    if [[ -d "$BACKUP_BASE" ]]; then
        local backup_count
        backup_count="$(ls -1 "$BACKUP_BASE" 2>/dev/null | wc -l | tr -d ' ')"
        log_info "Backups: $backup_count snapshots in $BACKUP_BASE"
    fi
}

# ─── RESET ────────────────────────────────────────────────────

do_reset() {
    log_header "Reset ai-config"
    echo ""
    echo -e "  This will ${RED}delete all config files${NC} and leave empty directories."
    echo -e "  You can then run ${CYAN}./ai-config.sh init${NC} to pull your own configs."
    echo ""
    read -r -p "  Are you sure? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        log_info "Cancelled"
        return 0
    fi

    for tool in "${ALL_TOOLS[@]}"; do
        local dir="$SCRIPT_DIR/$tool"
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -delete
            find "$dir" -type l -delete
            log_success "Cleared $tool/"
        fi
    done

    echo ""
    log_success "Reset complete. Run ${CYAN}./ai-config.sh init${NC} to populate with your configs."
}

# ─── PROJECT ──────────────────────────────────────────────────

# Project directly from ~/.claude/ to other tool home dirs (bypasses repo)
do_project() {
    local tool="${1:-all}"

    log_header "Project from ~/.claude/ → tool home dirs"
    log_info "Source: $CLAUDE_HOME (live, bypassing repo)"
    echo ""

    # Temporarily point CLAUDE_SOURCE_DIR at ~/.claude/
    local orig_claude_source_dir="$CLAUDE_SOURCE_DIR"
    CLAUDE_SOURCE_DIR="$CLAUDE_HOME"

    local projected=()
    for t in "${ALL_TOOLS[@]}"; do
        # Skip claude itself — it IS the source
        if [[ "$t" == "claude" ]]; then continue; fi
        if [[ "$tool" == "all" || "$tool" == "$t" ]]; then
            "apply_${t}"
            projected+=("$t")
        fi
    done

    CLAUDE_SOURCE_DIR="$orig_claude_source_dir"

    echo ""
    if [[ ${#projected[@]} -eq 0 ]]; then
        log_warn "No tools projected (tool: $tool)"
    else
        log_success "Projected to: ${projected[*]}"
        log_info "Verify with: ${CYAN}./ai-config.sh status${NC}"
    fi
}

# ─── MAIN ─────────────────────────────────────────────────────

usage() {
    echo -e "${BOLD}ai-config${NC} — Cross-AI tool configuration manager"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  ./ai-config.sh <command> [tool]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  init [tool]     Gather configs from tool home directories into ai-config/"
    echo "  apply [tool]    Deploy configs from ai-config/ to tool home directories"
    echo "  project [tool]  Project directly from ~/.claude/ to other tool home dirs (bypasses repo)"
    echo "  status [tool]   Show diff between ai-config/ and current tool configs"
    echo "  list            List managed tools and file counts"
    echo "  reset           Clear all configs, leave empty skeleton"
    echo ""
    echo -e "${BOLD}Tools:${NC}"
    echo "  claude          Claude Code (~/.claude/)"
    echo "  codex           Codex CLI (~/.codex/)"
    echo "  agy             Antigravity CLI (~/.gemini/antigravity-cli/)"
    echo "  all             All supported tools (default)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./ai-config.sh init              # Gather all tool configs"
    echo "  ./ai-config.sh apply claude      # Deploy only Claude configs"
    echo "  ./ai-config.sh project           # Project ~/.claude/ to all other tools"
    echo "  ./ai-config.sh project codex     # Project ~/.claude/ to Codex only"
    echo "  ./ai-config.sh status            # Show all diffs"
    echo ""
    echo -e "${BOLD}Safety:${NC}"
    echo "  • Backups created automatically before apply/project (~/.ai-config-backup/)"
    echo "  • Credential files are never copied"
    echo "  • Codex [projects.*] blocks preserved during apply/project"
}

resolve_tool() {
    local tool="${1:-all}"
    case "$tool" in
        claude|codex|agy|antigravity|antigravity-cli|antigravity_cli|all)
            case "$tool" in
                antigravity|antigravity-cli|antigravity_cli) echo "agy" ;;
                *) echo "$tool" ;;
            esac
            ;;
        *) log_error "Unknown tool: $tool"; exit 1 ;;
    esac
}

run_for_tools() {
    local action="$1" tool="$2"
    for t in "${ALL_TOOLS[@]}"; do
        if [[ "$tool" == "all" || "$tool" == "$t" ]]; then
            "${action}_${t}"
        fi
    done
}

main() {
    local cmd="${1:-}"

    if [[ -z "$cmd" ]]; then
        usage
        exit 0
    fi

    shift
    local tool
    tool="$(resolve_tool "${1:-all}")"

    case "$cmd" in
        init)
            run_for_tools "init" "$tool"
            echo ""
            log_success "Init complete. Review with: ${CYAN}./ai-config.sh status${NC}"
            ;;
        apply)
            run_for_tools "apply" "$tool"
            echo ""
            log_success "Apply complete. Verify with: ${CYAN}./ai-config.sh status${NC}"
            ;;
        project)
            do_project "$tool"
            ;;
        status)
            for t in "${ALL_TOOLS[@]}"; do
                if [[ "$tool" == "all" || "$tool" == "$t" ]]; then
                    status_tool "$t"
                fi
            done
            log_header "Shared skill mirrors"
            check_shared_mirrors
            log_header "Plugin drift"
            check_plugin_drift
            ;;
        list)   do_list ;;
        reset)  do_reset ;;
        help|--help|-h) usage ;;
        *)
            log_error "Unknown command: $cmd"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
