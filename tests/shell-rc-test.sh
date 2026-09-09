#!/usr/bin/env bash
# Tests setup:shell, the task that owns ~/.zshrc and ~/.bashrc.
#
# The rc files are the one place this repository writes into a file that is
# entirely the machine's, and the failure modes are quiet ones:
#
#   1. running against a mise that predates `mise bootstrap` — the blocks are
#      simply never written, and the shell comes up without mise on PATH
#   2. leaving the lines install.sh used to append — mise owns only what is
#      between its markers, so the machine ends up evaluating `mise activate`
#      twice per shell and sourcing the update notice twice
#   3. removing more than those exact lines, which is somebody's rc file gone
#   4. install.sh appending them again behind the task's back
#
# The task is a one-line delegation to .dotfiles/setup/shell.sh, so the script
# is what runs here — the same file setup:scripts places on a machine — with
# mise stubbed out, the way tests/oci-plugin-test.sh stubs it.
#
# Run it by hand, or in CI:
#   bash tests/shell-rc-test.sh

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
task_script="$repo/.dotfiles/setup/shell.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  # The whole line, so a case can vary the shape of it and not just the number.
  printf '%s\n' "$MISE_STUB_VERSION"
  exit 0
fi
printf '%s\n' "$*" >> "$CALL_LOG"
SH
chmod +x "$tmp/bin/mise"

home="$tmp/home"
calls="$tmp/calls"

fresh_home() {
  rm -rf "$home"
  mkdir -p "$home/.config/dotfiles"
  : > "$calls"
}

run_task() {
  local version="${1:-2026.9.2 linux-x64 (2026-09-07)}"
  PATH="$tmp/bin:$PATH" HOME="$home" MISE_STUB_VERSION="$version" CALL_LOG="$calls" \
    bash "$task_script"
}

fail() {
  echo "✗ $1" >&2
  exit 1
}

# The lines install.sh appended before mise took the rc files over, exactly as
# it wrote them: a comment, then one command.
legacy_wiring() {
  printf '%s\n' \
    'export EDITOR=vim' \
    '' \
    '# mise activation' \
    "eval \"\$(mise activate $1)\"" \
    '' \
    '# dotfiles update notification' \
    "source \"$home/.config/dotfiles/update-notice.sh\""
}

# --- 1. the version gate -----------------------------------------------------
# `mise bootstrap` exists from 2026.7.0 but is experimental until 2026.8.0, and
# this repository keeps experimental off. Applying against either would fail
# with mise's own error; the point of the gate is that the task says which
# problem this is, and says it before touching an rc file.
for too_old in "2025.12.0 linux-x64 (2025-12-04)" "2026.5.0" "2026.7.0 macos-arm64 (2026-07-02)" "mise 2026.7.9"; do
  fresh_home
  legacy_wiring zsh > "$home/.zshrc"
  if output="$(run_task "$too_old" 2>&1)"; then
    fail "setup:shell exited 0 on mise $too_old, which cannot apply the blocks"
  fi
  if [[ "$output" != *"needs mise 2026.8.0 or newer"* ]]; then
    fail "setup:shell does not name the mise version it needs on $too_old: $output"
  fi
  if [[ -s "$calls" ]]; then
    fail "setup:shell ran mise on $too_old: $(cat "$calls")"
  fi
  if [[ "$(cat "$home/.zshrc")" != "$(legacy_wiring zsh)" ]]; then
    fail "setup:shell edited ~/.zshrc on $too_old, where it cannot finish the job"
  fi
done

for supported in "2026.8.0" "2026.9.2 linux-x64 (2026-09-07)" "mise 2027.1.0"; do
  fresh_home
  run_task "$supported" > /dev/null
  if [[ ! -s "$calls" ]]; then
    fail "setup:shell refused to run on mise $supported"
  fi
done

# --- 2. what it asks mise to do ---------------------------------------------
# -C "$HOME" keeps the apply off whatever directory `mise run` was invoked from:
# a project mise.toml there would otherwise contribute its own [dotfiles]
# entries to the set being applied.
fresh_home
run_task > /dev/null
expected="$(printf '%s\n%s\n' \
  "-C $home bootstrap mise-shell-activate apply --yes" \
  "-C $home bootstrap dotfiles apply --yes")"
if [[ "$(cat "$calls")" != "$expected" ]]; then
  fail "setup:shell drove mise differently than expected:
  expected: $expected
  actual:   $(cat "$calls")"
fi

# --- 3. the pre-mise wiring is removed --------------------------------------
for shell in zsh bash; do
  case "$shell" in
    zsh) rc_name=".zshrc" ;;
    bash) rc_name=".bashrc" ;;
  esac
  fresh_home
  legacy_wiring "$shell" > "$home/$rc_name"
  chmod 600 "$home/$rc_name"
  run_task > /dev/null

  remaining="$(cat "$home/$rc_name")"
  if [[ "$remaining" == *"mise activate"* || "$remaining" == *"update-notice.sh"* ]]; then
    fail "setup:shell left the pre-mise wiring in ~/$rc_name:
$remaining"
  fi
  if [[ "$remaining" != *"export EDITOR=vim"* ]]; then
    fail "setup:shell removed more than the wiring from ~/$rc_name:
$remaining"
  fi
  # GNU stat first, BSD stat second: this suite runs on both.
  if [[ "$(stat -c '%a' "$home/$rc_name" 2> /dev/null || stat -f '%Lp' "$home/$rc_name")" != "600" ]]; then
    fail "setup:shell did not preserve the mode of ~/$rc_name"
  fi

  # The file it rewrote is the machine's own, and nothing else keeps a copy.
  backup="$(find "$home/.config/dotfiles/backup" -name "$rc_name" -type f 2> /dev/null | head -1)"
  if [[ -z "$backup" ]]; then
    fail "setup:shell rewrote ~/$rc_name without backing it up"
  fi
  if [[ "$(cat "$backup")" != "$(legacy_wiring "$shell")" ]]; then
    fail "the backup of ~/$rc_name is not what the task found there"
  fi
done

# --- 4. and nothing else is -------------------------------------------------
# Both lines of a pair have to match. A comment that introduces something else,
# or a command that mise did not write and this task cannot recognise, is the
# user's — leaving it in place is a doubled `mise activate` at worst, while
# removing it is somebody's configuration gone.
fresh_home
# shellcheck disable=SC2016  # these are rc-file lines, not expressions to expand
kept="$(printf '%s\n' \
  '# mise activation' \
  'export MISE_ENV=work' \
  '# dotfiles update notification' \
  'echo "checked for updates"' \
  'eval "$(mise activate zsh --shims)"' \
  'source "$HOME/.config/dotfiles/update-notice.sh"')"
printf '%s\n' "$kept" > "$home/.zshrc"
run_task > /dev/null
if [[ "$(cat "$home/.zshrc")" != "$kept" ]]; then
  fail "setup:shell removed lines it does not own:
$(cat "$home/.zshrc")"
fi
if [[ -d "$home/.config/dotfiles/backup" ]]; then
  fail "setup:shell took a backup of an rc file it did not change"
fi

# An rc file that does not exist is mise's to create, not this task's.
fresh_home
run_task > /dev/null
if [[ -e "$home/.zshrc" || -e "$home/.bashrc" ]]; then
  fail "setup:shell created an rc file itself; the blocks are mise's to write"
fi

# --- 5. install.sh does not write the rc files any more ---------------------
# The two `grep || cat >>` blocks that used to live at the end of install.sh are
# what setup:shell replaced. Re-adding them would put an unmarked copy of both
# lines back beside the blocks mise manages.
# shellcheck disable=SC2016  # the literal text grepped for in install.sh
if grep -qE '>>\s*"\$SHELL_CONFIG"' "$repo/install.sh"; then
  fail "install.sh appends to \$SHELL_CONFIG again; setup:shell owns the rc files"
fi
if ! grep -q 'setup:shell' "$repo/install.sh"; then
  fail "install.sh does not say who writes the shell startup files now"
fi

# --- 6. the declaration the script applies ----------------------------------
# The script only runs `apply`; everything it writes is declared in .mise.toml.
# A block that names one shell, or that sources the update notice without
# checking that it is there, is a broken shell on some machine.
if python3 -c 'import tomllib' 2> /dev/null; then
  py=(python3)
elif command -v uv > /dev/null 2>&1; then
  py=(uv run --quiet --python 3.12 python)
else
  echo "– no Python 3.11+ or uv; skipping the .mise.toml declaration checks"
  py=()
fi

if [[ ${#py[@]} -gt 0 ]]; then
  "${py[@]}" - "$repo" <<'PY'
import sys
import tomllib
from pathlib import Path

config = tomllib.loads((Path(sys.argv[1]) / ".mise.toml").read_text())
failures = 0


def fail(message):
    global failures
    failures += 1
    print(f"✗ {message}")


activate = config.get("bootstrap", {}).get("mise_shell_activate", {})
for target in ("zshrc", "bashrc"):
    if activate.get(target) != "activate":
        fail(f"[bootstrap.mise_shell_activate].{target} must be \"activate\", not {activate.get(target)!r}")

dotfiles = config.get("dotfiles", {})
for target in ("~/.zshrc/dotfiles-update-notice", "~/.bashrc/dotfiles-update-notice"):
    entry = dotfiles.get(target)
    if entry is None:
        fail(f"[dotfiles] declares no {target} block, so that shell never gets the update notice")
        continue
    block = entry.get("block", "")
    if "update-notice.sh" not in block:
        fail(f"the {target} block does not source the update notice")
    if "-r " not in block:
        fail(f"the {target} block sources the update notice without checking that it exists")

setup = config["tasks"]["setup"]["depends"]
if "setup:shell" not in setup:
    fail("the aggregate setup task does not run setup:shell, so a machine never gets the blocks")
if "setup:update-notice" not in config["tasks"]["setup:shell"]["depends"]:
    fail("setup:shell does not depend on setup:update-notice, which places the file its block sources")

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)
PY
fi

echo "shell rc tests passed"
