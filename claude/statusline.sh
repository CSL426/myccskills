#!/usr/bin/env bash
# Claude Code statusline script
# Reads JSON from stdin and outputs a compact single-line status

input=$(cat)

FIELDS='.version
.model.display_name
.agent.name
.worktree.name
.context_window.remaining_percentage
.cost.total_cost_usd
.cost.total_duration_ms
.rate_limits.five_hour.used_percentage
.rate_limits.five_hour.resets_at
.rate_limits.seven_day.used_percentage
.rate_limits.seven_day.resets_at'

# Read every field in one pass. Git Bash on Windows ships without jq, so fall
# back to the Node runtime Claude Code already depends on; give up quietly only
# when neither exists, since a broken statusline should not spam the prompt.
if command -v jq >/dev/null 2>&1; then
    parsed=$(printf '%s' "$input" | jq -r "[$(echo "$FIELDS" | paste -sd, -)] | map(. // \"\") | @tsv" 2>/dev/null | tr '\t' '\n')
elif command -v node >/dev/null 2>&1; then
    parsed=$(printf '%s' "$input" | node -e '
let raw = "";
process.stdin.on("data", (d) => (raw += d)).on("end", () => {
  let data;
  try { data = JSON.parse(raw); } catch { process.exit(0); }
  const paths = process.argv[1].split("\n");
  const read = (p) =>
    p.replace(/^\./, "").split(".").reduce((o, k) => (o == null ? o : o[k]), data);
  console.log(paths.map((p) => read(p) ?? "").join("\n"));
});' "$FIELDS" 2>/dev/null)
else
    exit 0
fi

{
    read -r version
    read -r model
    read -r agent_name
    read -r worktree_name
    read -r remaining_pct
    read -r cost_usd
    read -r duration_ms
    read -r five_hour_pct
    read -r five_hour_resets
    read -r weekly_pct
    read -r weekly_resets
} <<< "$parsed"

# --- ANSI colors ---
reset='\033[0m'
green='\033[32m'
yellow='\033[33m'
red='\033[31m'
dim='\033[2m'
bold='\033[1m'
cyan='\033[36m'
magenta='\033[35m'
blue='\033[34m'

# --- Helper: pick color by thresholds ---
# context_color <remaining_pct>
context_color() {
  local pct="$1"
  if awk "BEGIN{exit !($pct < 15)}"; then
    printf '%s' "$red"
  elif awk "BEGIN{exit !($pct < 30)}"; then
    printf '%s' "$yellow"
  else
    printf '%s' "$green"
  fi
}

# rate_color <used_pct>
rate_color() {
  local pct="$1"
  if awk "BEGIN{exit !($pct > 90)}"; then
    printf '%s' "$red"
  elif awk "BEGIN{exit !($pct > 70)}"; then
    printf '%s' "$yellow"
  else
    printf '%s' "$green"
  fi
}

# --- Helper: build 10-char progress bar for context ---
# filled chars = remaining percentage scaled to 10
# uses ░ for used, ▓ for remaining
build_bar() {
  local pct="$1"
  local filled
  filled=$(awk "BEGIN{printf \"%d\", ($pct / 100) * 10 + 0.5}")
  local used=$((10 - filled))
  local bar=""
  local i
  for ((i=0; i<used; i++));   do bar="${bar}░"; done
  for ((i=0; i<filled; i++)); do bar="${bar}▓"; done
  printf '%s' "$bar"
}

# --- Helper: relative time from unix epoch seconds ---
relative_time() {
  local target="$1"
  # resets_at may arrive as unix seconds or as an ISO-8601 timestamp; arithmetic
  # on the latter aborts the line with a bash "value too great for base" error.
  case "$target" in
    ''|*[!0-9]*)
      target=$(date -d "$target" +%s 2>/dev/null) || return
      [ -n "$target" ] || return
      ;;
  esac
  local now
  now=$(date +%s)
  local diff=$((target - now))
  if [ "$diff" -le 0 ]; then
    printf 'now'
    return
  fi
  local hours=$((diff / 3600))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    printf '%dh%dm' "$hours" "$mins"
  else
    printf '%dm' "$mins"
  fi
}

# --- Helper: format duration ---
format_duration() {
  local ms="$1"
  local sec=$((ms / 1000))
  local mins=$((sec / 60))
  local secs=$((sec % 60))
  if [ "$mins" -gt 0 ]; then
    printf '%dm%ds' "$mins" "$secs"
  else
    printf '%ds' "$secs"
  fi
}

# --- Helper: join parts with separator ---
join_parts() {
  local sep=" | "
  local line=""
  local first=1
  for part in "$@"; do
    if [ "$first" -eq 1 ]; then
      line="$part"
      first=0
    else
      line="${line}${sep}${part}"
    fi
  done
  printf '%s' "$line"
}

# --- Line 1: model, version, agent, worktree, cost, duration ---
line1=()

if [ -n "$model" ]; then
  line1+=("$(printf "${bold}${cyan}%s${reset}" "$model")")
fi

if [ -n "$version" ]; then
  line1+=("$(printf "${dim}v%s${reset}" "$version")")
fi

if [ -n "$agent_name" ]; then
  line1+=("$(printf "${magenta}🤖 %s${reset}" "$agent_name")")
fi

if [ -n "$worktree_name" ]; then
  line1+=("$(printf "${cyan}🌳 %s${reset}" "$worktree_name")")
fi

if [ -n "$cost_usd" ]; then
  cost_fmt=$(awk "BEGIN{printf \"%.2f\", $cost_usd}")
  line1+=("$(printf "${yellow}💰 \$%s${reset}" "$cost_fmt")")
fi

if [ -n "$duration_ms" ]; then
  dur=$(format_duration "$duration_ms")
  line1+=("$(printf "${dim}⏱️ %s${reset}" "$dur")")
fi

# --- Line 2: context bar, tokens, rate limit ---
line2=()

if [ -n "$remaining_pct" ]; then
  remaining_int=$(awk "BEGIN{printf \"%d\", $remaining_pct + 0.5}")
  color=$(context_color "$remaining_pct")
  bar=$(build_bar "$remaining_pct")
  line2+=("$(printf "${color}%s %d%% left${reset}" "$bar" "$remaining_int")")
fi

if [ -n "$five_hour_pct" ]; then
  used_int=$(awk "BEGIN{printf \"%d\", $five_hour_pct + 0.5}")
  color=$(rate_color "$five_hour_pct")
  resets_str=""
  if [ -n "$five_hour_resets" ]; then
    resets_str=" (resets $(relative_time "$five_hour_resets"))"
  fi
  line2+=("$(printf "⚡ 5h: ${color}%d%%${reset}%s" "$used_int" "$resets_str")")
fi

if [ -n "$weekly_pct" ]; then
  weekly_int=$(awk "BEGIN{printf \"%d\", $weekly_pct + 0.5}")
  color=$(rate_color "$weekly_pct")
  resets_str=""
  if [ -n "$weekly_resets" ]; then
    resets_str=" (resets $(relative_time "$weekly_resets"))"
  fi
  line2+=("$(printf "📅 7d: ${color}%d%%${reset}%s" "$weekly_int" "$resets_str")")
fi

# --- Output ---
echo -e "$(join_parts "${line1[@]}")"
echo -e "$(join_parts "${line2[@]}")"
