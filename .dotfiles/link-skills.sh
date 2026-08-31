#!/usr/bin/env bash
# Links this repository's own skills into the agent skill directories from a
# checkout, instead of letting `skills add` copy them there.
#
# A copy is a second source of truth. An agent that edits an installed skill
# edits a file nothing tracks, and the next `mise run setup:skills` throws that
# edit away without saying so. Through a symlink the same edit lands in the
# checkout's working tree, where `git status` shows it and the only way to
# reach another machine is a PR.
#
# Run by the `setup:skills` mise task, which downloads this script rather than
# keeping it inline in .mise.toml. The task falls back to `skills add` when
# this exits non-zero, so a machine that cannot get a checkout still has the
# skill — as a copy.
set -uo pipefail

REPO_PATH='github.com/bmthd/dotfiles'
CLONE_URL='https://github.com/bmthd/dotfiles'

# `skills add` installs into ~/.agents/skills, which OpenCode and Cursor read
# directly, and points Claude Code's own directory at it with a symlink. Keep
# that shape: the universal directory carries the link to the checkout, and
# Claude Code gets a link of its own, since on a machine where `skills add`
# never ran for this repository nothing else creates one.
universal_dir="$HOME/.agents/skills"
claude_dir="$HOME/.claude/skills"
# The skills CLI tracks what it installed here, and `npx skills update` acts on
# every entry — including one whose files are now a symlink, which it replaces
# with a fresh copy. Dropping the entry is what makes the link survive.
lock_file="$HOME/.agents/.skill-lock.json"

is_checkout() {
    [ -n "$1" ] && [ -d "$1/.agents/skills" ]
}

# ghq can be on PATH as a shim and still fail (`No version is set for shim:
# ghq`), so every use below judges it by what it printed, never by its status.
ghq_root() {
    local root
    root="$(ghq root 2> /dev/null | head -n 1)"
    case "$root" in
        /*) printf '%s\n' "$root" ;;
        *) printf '%s\n' "$HOME/ghq" ;;
    esac
}

find_checkout() {
    local candidate
    for candidate in \
        "${DOTFILES_REPO:-}" \
        "$(ghq list --full-path --exact "$REPO_PATH" 2> /dev/null | head -n 1)" \
        "$(ghq_root)/$REPO_PATH"; do
        if is_checkout "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Only ever clones, and clones the branch rather than the revision install.sh
# pinned: everything else that revision installs is an artifact nobody edits,
# while this is a working tree whose whole point is that a change made in it can
# be committed and opened as a PR — which a detached HEAD makes awkward. Moving
# a checkout that already exists is `/dotfiles apply`'s business: this script
# cannot tell a stale checkout from one deliberately parked on a branch, and
# pulling under the second would discard work.
acquire_checkout() {
    local dest
    ghq get "$REPO_PATH" > /dev/null 2>&1
    if find_checkout; then
        return 0
    fi
    dest="$(ghq_root)/$REPO_PATH"
    mkdir -p "$(dirname "$dest")" || return 1
    git clone --quiet "$CLONE_URL" "$dest" > /dev/null 2>&1 || return 1
    is_checkout "$dest" || return 1
    printf '%s\n' "$dest"
}

# True when $2 is a copy of $1 as some commit had it, rather than something
# someone typed. The working tree is the common case; the revision this machine
# installed from covers the one that is just as ordinary — a copy `skills add`
# wrote from an older commit, which differs from the working tree through no
# fault of the machine it sits on.
is_installed_copy() {
    local skill="$1" copy="$2" rel revision snapshot verdict
    diff -r -q "$skill" "$copy" > /dev/null 2>&1 && return 0

    revision="$(cat "$HOME/.config/dotfiles/revision" 2> /dev/null)" || return 1
    [ -n "$revision" ] || return 1
    rel="${skill#"$repo"/}"
    snapshot="$(mktemp -d)" || return 1
    verdict=1
    if git -C "$repo" archive "$revision" -- "$rel" 2> /dev/null | tar -x -C "$snapshot" 2> /dev/null; then
        diff -r -q "$snapshot/$rel" "$copy" > /dev/null 2>&1 && verdict=0
    fi
    rm -rf "$snapshot"
    return "$verdict"
}

# Replaces whatever occupies $link with a symlink to $skill. A directory there
# is what `skills add` left behind: one this repository can account for holds
# nothing to lose, but one it cannot may be an edit that exists nowhere else,
# so that one is moved aside rather than deleted.
link_skill() {
    local skill="$1" link="$2" aside
    if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$skill" ] && return 0
        rm -f "$link"
    elif [ -d "$link" ]; then
        if is_installed_copy "$skill" "$link"; then
            rm -rf "$link"
        else
            aside="$link.local.$(date -u +%Y%m%dT%H%M%SZ)"
            mv "$link" "$aside" || return 1
            echo "⚠ $link matched no revision of the checkout; kept as $aside"
        fi
    elif [ -e "$link" ]; then
        echo "⚠ $link exists and is not a skill directory; leaving it alone"
        return 1
    fi
    ln -sfn "$skill" "$link"
}

# Leaves an entry the CLI still owns alone: only the skills linked here are
# no longer the CLI's to update.
deregister_skill() {
    local name="$1" updated
    [ -f "$lock_file" ] || return 0
    if ! command -v jq > /dev/null 2>&1; then
        echo "⚠ jq not found; \`npx skills update\` will replace the $name link with a copy"
        return 0
    fi
    jq -e --arg name "$name" 'has("skills") and (.skills | has($name))' "$lock_file" > /dev/null 2>&1 || return 0
    updated="$(mktemp)"
    if jq --arg name "$name" 'del(.skills[$name])' "$lock_file" > "$updated" 2> /dev/null; then
        mv "$updated" "$lock_file"
    else
        rm -f "$updated"
        echo "⚠ Failed to drop $name from $lock_file; \`npx skills update\` may replace its link with a copy"
    fi
}

repo="$(find_checkout || acquire_checkout)"
# A trailing slash here would survive into the paths derived from it below.
repo="${repo%/}"
if ! is_checkout "$repo"; then
    echo "⚠ No usable bmthd/dotfiles checkout to link skills from"
    exit 1
fi

mkdir -p "$universal_dir" "$claude_dir"

linked=0
for skill in "$repo"/.agents/skills/*/; do
    [ -f "$skill/SKILL.md" ] || continue
    skill="${skill%/}"
    name="$(basename "$skill")"
    link_skill "$skill" "$universal_dir/$name" || continue
    link_skill "$skill" "$claude_dir/$name" || continue
    deregister_skill "$name"
    linked=$((linked + 1))
    echo "✓ $name skill linked to $skill"
done

if [ "$linked" -eq 0 ]; then
    echo "⚠ $repo holds no skill to link"
    exit 1
fi
