#!/usr/bin/env bash
# Claude Code status line — single line:
#   📁 <cwd>  ·  🌿 <worktree>(only in a linked worktree)  ·  <gauge> <ctx%>  ·  🧠 <model>
#
# Claude Code pipes a JSON payload to this script on stdin. Relevant fields:
#   .workspace.current_dir  current working directory
#   .model.display_name     human-readable model name
#   .transcript_path        JSONL transcript (used to compute context usage)
#   .exceeds_200k_tokens    true when the 1M-token context window is active
set -uo pipefail

input="$(cat)"

# ---- ANSI helpers ---------------------------------------------------------
esc=$'\033'
RESET="${esc}[0m"; DIM="${esc}[2m"; BOLD="${esc}[1m"
CYAN="${esc}[36m"; GREEN="${esc}[32m"; YELLOW="${esc}[33m"; RED="${esc}[31m"; MAGENTA="${esc}[35m"
SEP=" ${DIM}·${RESET} "

have_jq() { command -v jq >/dev/null 2>&1; }

# ---- parse payload --------------------------------------------------------
if have_jq; then
  cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')"
  model="$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
  exceeds="$(printf '%s' "$input" | jq -r '.exceeds_200k_tokens // false')"
else
  cwd="$PWD"; model="?"; transcript=""; exceeds="false"
fi
[ -n "${cwd:-}" ] || cwd="$PWD"

# ---- working directory (~-abbreviated, last 2 components if long) ---------
dir="${cwd/#$HOME/\~}"
short_dir="$(printf '%s' "$dir" | awk -F/ '{ if (NF>3) printf "…/%s/%s", $(NF-1), $NF; else print $0 }')"

# ---- worktree (only shown inside a linked git worktree) -------------------
worktree=""
if git_dir="$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)"; then
  common_dir="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)"
  abs() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s' "$PWD" "$(basename "$1")"); }
  if [ "$(abs "$git_dir")" != "$(abs "$common_dir")" ]; then
    worktree="$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")"
  fi
fi

# ---- context usage (from latest transcript usage record) ------------------
gauge=""; pct_label=""
if [ -n "$transcript" ] && [ -f "$transcript" ] && have_jq; then
  tokens="$(jq -rs '
    [ .[] | select(.message.usage != null) ] | last | .message.usage
    | ( (.input_tokens // 0)
      + (.cache_read_input_tokens // 0)
      + (.cache_creation_input_tokens // 0) )' "$transcript" 2>/dev/null)"
  if [[ "${tokens:-}" =~ ^[0-9]+$ ]]; then
    if [ "$exceeds" = "true" ]; then window=1000000; else window=200000; fi
    pct=$(( tokens * 100 / window ))
    [ "$pct" -gt 100 ] && pct=100
    # colour by pressure
    if   [ "$pct" -lt 50 ]; then col="$GREEN"
    elif [ "$pct" -lt 80 ]; then col="$YELLOW"
    else col="$RED"; fi
    width=10; filled=$(( pct * width / 100 )); bar=""
    for ((i=0;i<width;i++)); do
      if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
    done
    gauge="${col}${bar}${RESET}"
    pct_label="${col}${pct}%${RESET}"
  fi
fi

# ---- compose --------------------------------------------------------------
line="${CYAN}📁 ${short_dir}${RESET}"
[ -n "$worktree" ] && line+="${SEP}${MAGENTA}🌿 ${worktree}${RESET}"
[ -n "$gauge" ]    && line+="${SEP}${gauge} ${pct_label}"
line+="${SEP}${BOLD}🧠 ${model}${RESET}"

printf '%s' "$line"
