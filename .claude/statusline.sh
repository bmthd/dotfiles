#!/usr/bin/env bash
# Claude Code status line — single line:
#   📁 <cwd>  ·  🌿 <worktree>(only in a linked worktree)  ·  <gauge> <ctx%>  ·  🧠 <model>
#
# Claude Code pipes a JSON payload to this script on stdin. Relevant fields:
#   .workspace.current_dir  current working directory
#   .model.display_name     human-readable model name
#   .context_window         live context usage from the most recent API response
#   .transcript_path        JSONL transcript (fallback for older Claude Code)
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
else
  cwd="$PWD"; model="?"; transcript=""
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

# ---- context usage --------------------------------------------------------
# Claude Code reports the live context window in the payload, already scaled to
# the model's real window (200k, or 1M with extended context). Prefer it: it is
# what /context shows. Deriving the window from .exceeds_200k_tokens is wrong —
# that flag is a fixed 200k threshold on the last response, not a "1M window is
# active" signal, so it only flips *after* the gauge has already pinned at 100%.
pct=""
if have_jq; then
  pct="$(printf '%s' "$input" | jq -r '
    (.context_window // {}) as $c
    | ($c.context_window_size // 200000) as $size
    | ( $c.used_percentage
        // ( $c.current_usage
             | if . == null or $size <= 0 then null
               else ( ( (.input_tokens // 0)
                      + (.cache_creation_input_tokens // 0)
                      + (.cache_read_input_tokens // 0) ) * 100 / $size )
               end ) )
    | if . == null then empty else floor end' 2>/dev/null)"
fi

# Fallback for Claude Code versions that predate .context_window: read the last
# usage record from the transcript. Skip sidechain (subagent) records — their
# usage is the subagent's own context, not this conversation's.
if [ -z "${pct:-}" ] && [ -n "$transcript" ] && [ -f "$transcript" ] && have_jq; then
  pct="$(jq -rs '
    [ .[] | select(.type == "assistant" and .isSidechain != true and .message.usage != null) ]
    | last | .message.usage
    | if . == null then empty
      else ( ( (.input_tokens // 0)
             + (.cache_read_input_tokens // 0)
             + (.cache_creation_input_tokens // 0) ) * 100 / 200000 | floor )
      end' "$transcript" 2>/dev/null)"
fi

gauge=""; pct_label=""
if [[ "${pct:-}" =~ ^[0-9]+$ ]]; then
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

# ---- compose --------------------------------------------------------------
line="${CYAN}📁 ${short_dir}${RESET}"
[ -n "$worktree" ] && line+="${SEP}${MAGENTA}🌿 ${worktree}${RESET}"
[ -n "$gauge" ]    && line+="${SEP}${gauge} ${pct_label}"
line+="${SEP}${BOLD}🧠 ${model}${RESET}"

printf '%s' "$line"
