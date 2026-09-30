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

# ---- fit to width ---------------------------------------------------------
# Claude Code clips an over-long status line from the right, so in a narrow pane
# the gauge and model — the parts worth watching — are what disappear. Instead,
# give the cwd and worktree names only the room left after the gauge and model,
# shortening them in stages. COLUMNS is the only width source: Claude Code
# captures stdout, so tput cannot see the terminal. Without it, print in full.
#
# Display width: every non-ASCII character counts as 2 columns. That is right
# for the emoji and CJK names, and merely conservative for "…".
vis_width() {
  # C collation makes " -~" the ASCII range; under en_US.UTF-8 bash 3.2 (macOS
  # /bin/bash) collates it to match nearly everything.
  local LC_COLLATE=C
  local ascii="${1//[^ -~]/}"
  printf '%s' $(( ${#ascii} + (${#1} - ${#ascii}) * 2 ))
}
# Trim $1 to at most $2 columns, marking the cut with "…".
fit() {
  local s="$1" max="$2"
  [ "$(vis_width "$s")" -le "$max" ] && { printf '%s' "$s"; return; }
  while [ -n "$s" ] && [ $(( $(vis_width "$s") + 2 )) -gt "$max" ]; do s="${s%?}"; done
  printf '%s…' "$s"
}

# Columns taken by the parts that are never shortened: separators (3 each),
# the gauge ("<bar> <pct>%") and "🧠 <model>". The bar is counted apart from
# vis_width because its block characters are 1 column, not 2.
gauge_width() {
  if   [ -z "$pct_label" ]; then printf 0
  elif [ -n "$gauge" ];     then printf '%s' $(( ${#bar} + 1 + ${#pct} + 1 + 3 ))
  else                           printf '%s' $(( ${#pct} + 1 + 3 )); fi
}
budget() { # columns left for "📁 <dir>" and "🌿 <worktree>" together
  local b=$(( ${COLUMNS:-0} - $(gauge_width) - $(vis_width "🧠 $model") - 3 ))
  [ -n "$worktree" ] && b=$(( b - 3 ))
  printf '%s' "$b"
}
names_width() {
  local w; w=$(vis_width "📁 $short_dir")
  [ -n "$worktree" ] && w=$(( w + $(vis_width "🌿 $worktree") ))
  printf '%s' "$w"
}

if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && [ "$COLUMNS" -gt 0 ]; then
  min_name=10 # "📁 " plus a few characters: still recognisable
  # 1. Keep only the last path component.
  [ "$(names_width)" -gt "$(budget)" ] && short_dir="${dir##*/}"
  # 2. Split what is left evenly between the two names; a name shorter than
  #    its half hands the rest to the other. Neither goes below min_name.
  if [ "$(names_width)" -gt "$(budget)" ]; then
    avail=$(budget)
    dir_w=$(vis_width "📁 $short_dir")
    if [ -z "$worktree" ]; then
      dir_room=$avail
    else
      wt_w=$(vis_width "🌿 $worktree"); half=$(( avail / 2 ))
      if   [ "$dir_w" -le "$half" ]; then dir_room=$dir_w;           wt_room=$(( avail - dir_w ))
      elif [ "$wt_w" -le "$half" ];  then dir_room=$(( avail - wt_w )); wt_room=$wt_w
      else                                dir_room=$half;            wt_room=$(( avail - half )); fi
      [ "$wt_room" -lt "$min_name" ] && wt_room=$min_name
      worktree="$(fit "$worktree" $(( wt_room - 3 )))" # 3 = "🌿 "
    fi
    [ "$dir_room" -lt "$min_name" ] && dir_room=$min_name
    short_dir="$(fit "$short_dir" $(( dir_room - 3 )))" # 3 = "📁 "
  fi
  # 3. Drop the bar, keeping the percentage.
  if [ "$(names_width)" -gt "$(budget)" ] && [ -n "$gauge" ]; then
    bar=""; gauge=""
  fi
  # 4. Drop the names outright, worktree first.
  [ "$(names_width)" -gt "$(budget)" ] && worktree=""
  [ "$(names_width)" -gt "$(budget)" ] && short_dir=""
  # 5. Last resort: trim the model name so the percentage before it survives.
  if [ "$(budget)" -lt 0 ]; then
    room=$(( COLUMNS - $(gauge_width) - 3 )) # 3 = "🧠 "
    [ "$room" -lt 6 ] && room=6
    model="$(fit "$model" "$room")"
  fi
fi

# ---- compose --------------------------------------------------------------
parts=()
[ -n "$short_dir" ] && parts+=("${CYAN}📁 ${short_dir}${RESET}")
[ -n "$worktree" ]  && parts+=("${MAGENTA}🌿 ${worktree}${RESET}")
if [ -n "$pct_label" ]; then
  if [ -n "$gauge" ]; then parts+=("${gauge} ${pct_label}"); else parts+=("$pct_label"); fi
fi
parts+=("${BOLD}🧠 ${model}${RESET}")

line="${parts[0]}"
for part in "${parts[@]:1}"; do line+="${SEP}${part}"; done
printf '%s' "$line"
