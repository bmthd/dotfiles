# shellcheck shell=sh
# Where the mise files this repository installs go, and how to recognise the
# copy an older installation left behind.
#
# Sourced by both placers: `install.sh`, which fetches this file from the same
# pinned revision because it runs piped from curl with no checkout, and
# `.dotfiles/apply.sh`, which reads it out of the checkout it lives in. Issue
# #71 happened because the rules were written out twice and only one copy
# learned about the conf.d split, so `apply` kept writing the repository's
# config back to the file conf.d had freed. One definition is what stops that
# from happening a second time; adding a path here rather than in a caller is
# the point of the file.
#
# Everything here must parse and behave the same under bash and zsh: install.sh
# is documented to be piped into either. No arrays, no other bashisms.
#
# Sourcing this from install.sh executes code fetched over the network, but
# install.sh is itself code fetched over the network from the same repository
# at the same resolved commit, so it crosses no trust boundary the installation
# had not already crossed.

# The repository's copy of .mise.toml. conf.d/ rather than config.toml: mise
# merges every non-hidden .toml under conf.d/ into the global config and lets
# config.toml win, which leaves config.toml free for whatever one machine needs
# and gives re-runs nothing of the user's to overwrite.
dotfiles_mise_config_path() {
    printf '%s\n' "$1/.config/mise/conf.d/10-dotfiles.toml"
}

# The global lockfile. mise keys it to the config *directory*, so it belongs
# next to config.toml and never beside the fragment above — deriving it from
# the config path is exactly how `apply` came to look for conf.d/mise.lock.
dotfiles_mise_lock_path() {
    printf '%s\n' "$1/.config/mise/mise.lock"
}

# Where installations from before the conf.d split put the repository's config,
# and what still outranks conf.d for as long as it holds that copy.
dotfiles_legacy_mise_config_path() {
    printf '%s\n' "$1/.config/mise/config.toml"
}

# True when the file is this repository's copy rather than a config written for
# this machine. The marker is the raw.githubusercontent.com URL this
# repository's own setup tasks fetch from; a hand-written config.toml — the
# file's job from now on — does not contain it, so it is never touched.
dotfiles_is_repository_mise_config() {
    [ -f "$1" ] && grep -q 'raw.githubusercontent.com/bmthd/dotfiles' "$1" 2> /dev/null
}

# Escape hatch for someone who has already merged their side by hand, or who
# knows the old file holds nothing they want. Both placers honour it, so it
# means the same thing wherever the migration is attempted from.
dotfiles_migration_is_forced() {
    [ "${DOTFILES_MIGRATE_MISE_CONFIG:-}" = "1" ]
}
