#!/usr/bin/env bash
# `setup:shell`: write the blocks .mise.toml declares for the shell startup
# files. Placed by the setup:scripts task in .mise.toml; see the comment there.
#
# The two lines an interactive shell needs — mise's activation and the sourcing
# of the update notice — used to be `grep || cat >>` blocks at the end of
# install.sh. That made them a bootstrap step rather than state: they were
# written once, for whichever shell install.sh was piped into, and nothing could
# ever change them again. mise now owns both as marker-delimited blocks declared
# in [bootstrap.mise_shell_activate] and [dotfiles], and this task is what
# applies that declaration.
set -euo pipefail

# `mise bootstrap` arrived in 2026.7.0 but stayed behind `experimental = true`
# until 2026.8.0, and this repository keeps experimental off (see [settings] in
# .mise.toml). Checking the version rather than letting the commands below fail
# keeps "this mise is too old" apart from "applying the blocks failed", which
# are different problems with different fixes.
MINIMUM_MISE="2026.8.0"

# Field-by-field numeric compare. `sort -V` would be shorter, but this also runs
# on macOS, whose sort has no version sort.
version_at_least() {
    awk -v have="$1" -v want="$2" 'BEGIN {
        have_parts = split(have, h, ".")
        want_parts = split(want, w, ".")
        for (i = 1; i <= (have_parts > want_parts ? have_parts : want_parts); i++) {
            hv = (i <= have_parts ? h[i] + 0 : 0)
            wv = (i <= want_parts ? w[i] + 0 : 0)
            if (hv > wv) exit 0
            if (hv < wv) exit 1
        }
        exit 0
    }'
}

# The first field that looks like a version rather than $1: `mise --version`
# answers "2026.9.2 linux-x64 (2026-09-07)" today, and a wrapper or a future
# release prefixing the line with the program name must not read as 0.
# `|| true` because pipefail turns "mise is not on PATH" into a 127 that would
# abort the script before it could say what is wrong.
mise_version="$(mise --version 2>/dev/null |
    awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+/) { print $i; exit } }' || true)"
if [ -z "$mise_version" ]; then
    echo "⚠ Managing the shell startup files needs mise $MINIMUM_MISE or newer, and no mise is on PATH"
    exit 1
fi
if ! version_at_least "$mise_version" "$MINIMUM_MISE"; then
    echo "⚠ Managing the shell startup files needs mise $MINIMUM_MISE or newer; this machine has $mise_version, so update it (\`mise self-update\`) and re-run \`mise run setup:shell\`"
    exit 1
fi

# What install.sh appended before mise took these files over. mise only owns
# what is between its markers, so it has no way to see these lines: left in
# place they would make every interactive shell evaluate `mise activate` twice
# and source the update notice twice. Both lines of a pair have to match — a
# comment on its own is not enough — so a `# mise activation` someone else wrote
# above something else survives.
strip_legacy_wiring() {
    local rc="$1"
    local stripped backup

    [ -f "$rc" ] || return 0
    stripped="$(mktemp)"
    awk '
        pending != "" {
            if ((pending == "# mise activation" &&
                 $0 ~ /^eval "\$\(mise activate (bash|zsh)\)"$/) ||
                (pending == "# dotfiles update notification" &&
                 $0 ~ /^(source|\.) ".*\/\.config\/dotfiles\/update-notice\.sh"$/)) {
                pending = ""
                next
            }
            print pending
            pending = ""
        }
        $0 == "# mise activation" || $0 == "# dotfiles update notification" {
            pending = $0
            next
        }
        { print }
        END { if (pending != "") print pending }
    ' "$rc" > "$stripped"

    if cmp -s "$rc" "$stripped"; then
        rm -f "$stripped"
        return 0
    fi

    # This is the machine's file, not one this repository installs, and nothing
    # else keeps a copy of it — install.sh backs a migrated mise config up the
    # same way, into the same directory.
    backup="$HOME/.config/dotfiles/backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup"
    cp -p "$rc" "$backup/$(basename "$rc")"
    # Written through, not moved into place: the rc file may be a symlink into a
    # dotfiles checkout of its own, and its mode is the user's to keep.
    cat "$stripped" > "$rc"
    rm -f "$stripped"
    echo "✓ Removed the pre-mise wiring from $rc (backed up in $backup)"
}

strip_legacy_wiring "$HOME/.zshrc"
strip_legacy_wiring "$HOME/.bashrc"

# -C "$HOME" because `mise run` starts a task in the directory it was invoked
# from, and a mise.toml there contributes its own [dotfiles] entries to the set
# that gets applied. Shell startup files belong to the machine, not to whatever
# project the terminal happened to be sitting in, so this converges the global
# config only: this repository's conf.d fragment plus anything the machine
# declared for itself in ~/.config/mise/config.toml.
echo "📦 Applying the declared shell startup blocks..."
mise -C "$HOME" bootstrap mise-shell-activate apply --yes
mise -C "$HOME" bootstrap dotfiles apply --yes
