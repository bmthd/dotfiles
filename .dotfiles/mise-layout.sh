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

# --- profiles ---------------------------------------------------------------
# A machine installs .mise.toml plus at most one profile fragment beside it in
# conf.d/. The fragment inherits everything the common config declares and says
# only where that kind of machine differs (see .mise.work.toml for why the
# difference can only ever be a subtraction).

# Every profile this repository ships, as one space-separated word list so that
# a caller can iterate it under both shells. `personal` is the baseline and has
# no fragment of its own: it is the whole of .mise.toml, which is what every
# installation before profiles existed already had.
dotfiles_profiles() {
    printf '%s\n' 'personal work'
}

dotfiles_default_profile() {
    printf '%s\n' 'personal'
}

dotfiles_profile_is_known() {
    case " $(dotfiles_profiles) " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# The profile this machine was installed with. Recorded rather than inferred
# from what is in conf.d/, so that a re-run with no DOTFILES_PROFILE in the
# environment — which is every re-run months later, and every `/dotfiles apply`
# — keeps installing the same profile instead of silently reverting to the
# default.
dotfiles_profile_record_path() {
    printf '%s\n' "$1/.config/dotfiles/profile"
}

# The repository file holding a profile's fragment, relative to the repository
# root, and empty for a profile that has none. Empty is not an error: it is how
# `personal` says "the common config is the whole of it".
dotfiles_profile_repository_path() {
    case "$1" in
        personal) ;;
        *) printf '%s\n' ".mise.$1.toml" ;;
    esac
}

# Where that fragment goes, and empty for the same reason. The 20- prefix sorts
# it after 10-dotfiles.toml, which is what makes it the overlay rather than the
# overlaid.
dotfiles_profile_config_path() {
    case "$2" in
        personal) ;;
        *) printf '%s\n' "$1/.config/mise/conf.d/20-dotfiles-$2.toml" ;;
    esac
}
