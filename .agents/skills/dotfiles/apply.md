# /dotfiles apply — apply an available update to this machine

`install.sh` and `mise run setup` are written to **overwrite local state with the
remote's**. Per-machine circumstances — hand-edited settings, tools only this box
needs, hand-added hooks — do not exist in the repository, so a plain re-run deletes
them silently.

The mise config is the exception, and it is an exception by construction rather
than by care: the repository's copy goes to `~/.config/mise/conf.d/10-dotfiles.toml`
and `~/.config/mise/config.toml` is left to the machine, so there is nothing of the
user's in the file that gets replaced. Everything below still applies to the Claude
Code settings, which are merged rather than owned.

The job here is to **separate "changes to take" from "local divergence to keep"
before anything is overwritten**. Running `install.sh` without reading a diff first
defeats the entire point.

## Overwrite hazards

What a plain re-run does. This is the whole picture the decisions hang off.

| Target | A plain re-run | Handling |
|---|---|---|
| `~/.config/mise/conf.d/10-dotfiles.toml` | **Wholesale curl overwrite** from the repo's `.mise.toml` | **Overwrite it** (step 4). It holds no per-machine state, so there is nothing to merge |
| `~/.config/mise/config.toml` | **Never written.** Reserved for this machine, and mise loads it after conf.d, so it wins | Leave it alone. A machine installed before the conf.d split still has the repo's copy here — migrate it once (step 4) |
| `~/.claude/settings.json` | Deep merge via `jq -s '.[0] * .[1]'`, **remote wins on conflicts**; arrays (`permissions.allow` etc.) are **replaced, not concatenated** | **Apply by hand** (step 5). The biggest hazard left. Leave it alone when the repo has no diff |
| `~/.claude/statusline.sh` | **Wholesale curl overwrite** | Overwrite if unmodified locally; 3-way if not |
| `~/.config/dotfiles/update-notice.sh` | Wholesale curl overwrite | Safe to overwrite — holds no per-machine state |
| `~/.bashrc` / `~/.zshrc` | Append guarded by `grep` | Idempotent. Leave alone |
| Skills / plugins | `npx skills add -g`, `claude plugin install` | Idempotent, but mind `mise run` task `depends` (step 6) |
| Installed tools | `mise install` reads the merged config | **A preserved config does not mean working tools.** Verify in step 4 |

## Steps

### 1. Secure the merge base

The revision in `~/.config/dotfiles/revision` is the common ancestor that separates
repository changes from local edits. **The whole procedure depends on that object being
reachable**, so settle it first.

```bash
INSTALLED="$(cat ~/.config/dotfiles/revision 2>/dev/null)"
REPO="$(ghq root 2>/dev/null || echo ~/ghq)/github.com/bmthd/dotfiles"
ghq get -u github.com/bmthd/dotfiles || git clone https://github.com/bmthd/dotfiles "$REPO"
git -C "$REPO" fetch origin main
git -C "$REPO" cat-file -e "$INSTALLED^{commit}" 2>/dev/null && echo "BASE OK"
```

**Do not swallow failures from `ghq get` or `fetch`.** `ghq` can be on PATH as a shim
and still fail (`No version is set for shim: ghq`) — fall back to `git clone`. Without a
completed fetch you will compare against a stale `origin/main` and think it is current.

**If `BASE OK` does not print:**

- A force-push (rebase) of `main` **removes the installed revision from the remote**.
  That is what `fatal: bad object` means. Confirm it by looking for `(forced update)` in
  the `git fetch` output.
- Another checkout on this machine may still hold the object. Probe candidates with
  `git -C <candidate> cat-file -e "$INSTALLED^{commit}"` and use one **read-only** as
  `REPO` (no branch switching, no commits, no pushes).
- If no copy exists anywhere, or the revision file itself is missing, fall back to
  **no-base mode**: 3-way merging is impossible. Diff each local file against
  `origin/main` directly, apply **nothing** automatically, and settle every hunk with
  the user one at a time — "repository change" or "local edit".

Once the base is secured, look at what the repository changed:

```bash
git -C "$REPO" diff --stat "$INSTALLED" origin/main
```

### 2. Inventory the local divergence

Establish what is unique to this machine by comparing against the repository content
**as of installation**. Comparing against current `main` mixes repository updates with
local edits, and updates then get discarded as if they were local edits.

```bash
cat ~/.config/mise/config.toml 2>/dev/null            # this machine's own mise config
git -C "$REPO" show "$INSTALLED:.claude/statusline.sh" | diff - ~/.claude/statusline.sh
```

`config.toml` is read, not diffed: nothing in the repository corresponds to it, so
everything in it is machine-local by definition. On a machine that predates the
conf.d split it holds the repository's copy instead — step 4 migrates that.

Work through the hunks one at a time and confirm with the user why each exists. Pinned
versions, machine-only tools, and disabled settings are usually **deliberate, not
accidental**. Ask before removing any of them. When asking is impossible, **keep the
local side** and carry the item into the final report as an open question.

### 3. Back up

Always, before touching anything. Be ready to hand the user a restore command.

```bash
BK=~/.config/dotfiles/backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
cp ~/.config/mise/config.toml ~/.claude/settings.json ~/.claude/statusline.sh "$BK/" 2>/dev/null
cp ~/.config/mise/conf.d/10-dotfiles.toml "$BK/" 2>/dev/null
```

### 4. Replace the mise config fragment

**No 3-way merge here.** The repository's config is a conf.d fragment that owns
nothing machine-specific, so take it whole. Machine-local pins, extra tools and
local `[settings]` belong in `~/.config/mise/config.toml`, which mise loads after
conf.d and which nothing in this repository writes.

```bash
mise ls --installed | awk '{print $1}' | sort > "$W/tools.before"   # capture before installing
mkdir -p ~/.config/mise/conf.d
git -C "$REPO" show origin/main:.mise.toml > ~/.config/mise/conf.d/10-dotfiles.toml
git -C "$REPO" show origin/main:mise.lock  > ~/.config/mise/mise.lock
```

Take `mise.lock` with it. It is what turns the fragment's `latest` selectors into
exact versions, and mise keys the global lockfile to the config directory rather
than to a file name, so the one at `~/.config/mise/mise.lock` covers conf.d too.

**One-time migration for a machine installed before the split.** Its
`~/.config/mise/config.toml` still holds the repository's copy, and leaving it
there is worse than the overwrite it replaced: config.toml outranks conf.d, and
`[tasks]` are replaced whole rather than merged, so the stale copy would shadow
every task shipped from here.

```bash
grep -q 'raw.githubusercontent.com/bmthd/dotfiles' ~/.config/mise/config.toml 2>/dev/null &&
    mv ~/.config/mise/config.toml "$BK/config.toml.pre-conf.d"
```

Then diff what was moved against the fresh fragment and **carry only the
machine-local part into a new, otherwise empty `config.toml`**. The difference is
a mix of upstream change and local edit, so settle it hunk by hunk against step 2's
inventory, exactly as the old 3-way merge did — the difference is that this
happens once per machine rather than on every update.

```bash
diff "$BK/config.toml.pre-conf.d" ~/.config/mise/conf.d/10-dotfiles.toml
```

`install.sh` does only the provably safe half of this. It migrates the file when
it is identical either to the copy being installed or to the `.mise.toml` of the
revision recorded in `~/.config/dotfiles/revision` — meaning nothing was added
locally — and otherwise **leaves it exactly where it is** and says so. That is
deliberate: `mise install` and `mise run setup` run moments later in that script,
so moving a config.toml that pins a version would take the pin out of effect and
reinstall against the lockfile before anyone could read the warning. Reconstructing
the machine-local side is this procedure's job, not a bootstrapper's.

Then **verify the content, not just the parse**. `mise ls` exiting 0 proves very
little.

```bash
mise cfg   # conf.d/10-dotfiles.toml listed, config.toml after it if present
mise tasks ls >/dev/null || echo "!! config is broken — restore from the backup"
mise ls --installed | awk '{print $1}' | sort | diff "$W/tools.before" -
mise run --skip-tools setup:oci-plugin
mise install
```

`setup:oci-plugin` must run before `mise install`. Older installations left the
asdf OCI plugin under mise's `oci` plugin name; current mise resolves that name
through vfox and otherwise tries to load the old Bash plugin as Lua. The task
replaces only that legacy checkout and is a no-op once vfox is installed.

Parsing as TOML and being a correct mise config are different things. **Check that the
tools written in the config actually appear in `mise ls`.** A `[tools.xxx]` sub-table
heading absorbs every plain key that follows it as its own child, which can disable all
the later tools at once. The symptoms: `mise install` answers "all tools are installed"
instantly, yet `command -v` finds nothing and `No version is set for shim: <tool>`
appears at runtime. **This is a repository bug rather than something this machine
caused** — do not patch it locally; report it upstream with `/dotfiles pr`.

### 5. Apply only the repository's diff to the Claude Code settings

`~/.claude/settings.json` is a **merge product**, not a copy, so 3-way does not apply.
Look at what the repository changed and hand-apply **only that**.

```bash
git -C "$REPO" diff "$INSTALLED" origin/main -- .claude/settings.json
```

**No diff means do nothing** — the common case. When there is one:

- Repository **added** a key or permission entry → add it locally
- Repository **changed** a value where local holds its own → local wins; tell the user
- Arrays such as `permissions.allow` → take the **union**, never the replacement. Do not drop local entries
- Afterwards confirm the file is still valid JSON: `jq . ~/.claude/settings.json >/dev/null`

For `statusline.sh`, if step 2 showed no local diff, take `origin/main`'s copy. Read it
out of the fetched clone rather than curling the raw URL, to avoid CDN lag. **Do not
forget the executable bit or the test.**

```bash
git -C "$REPO" show origin/main:.claude/statusline.sh > ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
bash -n ~/.claude/statusline.sh && bash "$REPO/tests/statusline-test.sh"
```

If it was modified locally, 3-way merge it against `$INSTALLED` as the base.

### 6. Run the remaining tasks

**`mise run setup:codex` and `mise run setup:claude-plugins` both declare
`depends = ["setup:claude"]`.** Running them plainly pulls in `setup:claude`, which
deep-merges `settings.json` with remote priority and replaces `permissions.allow` —
undoing step 5. `--skip-deps` is mandatory.

```bash
mise run setup:skills
mise run --skip-deps setup:codex
mise run --skip-deps setup:claude-plugins
```

**Never** `mise run setup` (everything) or `mise run setup:claude`.

`npx skills update` **without `-g` looks at project skills and exits 0 having done
nothing** (`No project skills to update.`). This skill deals with global skills, so pass
`-g`. If `setup:skills` just reinstalled every source, it is redundant and can be skipped.

```bash
npx skills update -g -y   # -g, if you run it at all
```

**`setup:skills` reports success even when a source failed.** Every line in the task
runs through `install_skills`, which swallows the error and prints
`⚠ <label> skills installation failed (continuing)`. The task then exits 0, so a source
that installed nothing looks identical to one that worked. Read the task's output for
those warnings, and confirm each source actually landed:

```bash
npx skills list -g
```

Re-run a failed source by hand — the failures are usually transient:

```bash
npx skills add <source> -y -g -a claude-code -a opencode -a cursor
```

**Skills removed or renamed upstream stay installed.** `npx skills` refuses to delete
them in non-interactive mode and only prints a warning, so a rename leaves the old name
sitting next to the new one — two skills claiming the same job, which is worse than
either alone. Check the warnings against `npx skills list -g` and remove the leftovers:

```bash
npx skills remove <old-name> -g -y
```

### 7. Record the revision and report

Skip this and the next interactive shell announces the update all over again.

```bash
git -C "$REPO" rev-parse origin/main > ~/.config/dotfiles/revision
```

Re-fetch `update-notice.sh` only if step 1's diff touched it.

```bash
git -C "$REPO" show origin/main:.dotfiles/update-notice.sh > ~/.config/dotfiles/update-notice.sh
```

The notice watches `bmthd/skills` as well, and step 6's `mise run setup:skills` records
that revision on its way out. Record it by hand only if you re-ran a source with
`npx skills add` instead of running the task — and do it after the re-fetch above, since
an older copy of the script has no `record` subcommand and ignores it silently.

```bash
bash ~/.config/dotfiles/update-notice.sh record skills
```

Confirm the notification actually stopped.

```bash
rm -f ~/.config/dotfiles/last-update-check
bash -c 'source ~/.config/dotfiles/update-notice.sh; dotfiles_update_notice_check'  # silence means resolved
```

Then report to the user. **Item 4 is not optional** — it is where the accountability for
the judgment calls you made on their behalf lives.

1. Changes taken
2. Local divergence deliberately kept, and why
3. Backup location and how to restore
4. What should have been confirmed with the user: anything decided local-side without
   asking, and anything that needs reporting upstream as a repository bug

## Signs to stop and go back

| Sign | What it means |
|---|---|
| Ran `install.sh` before reading a diff | `~/.claude/settings.json` is already merged remote-first. Restore from backup and start over |
| Ignored a failing `ghq get` / `fetch` | You are judging against a stale `origin/main` |
| Kept 3-way merging `statusline.sh` without a base | `bad object`. Suspect a force-push and switch to no-base mode |
| Left a repo-derived `~/.config/mise/config.toml` in place | It outranks conf.d and replaces `[tasks]` whole, so every task stays frozen at the old copy |
| Judged local divergence against current `main` | Repository updates get discarded as local edits |
| Installed a file with conflict markers | mise cannot parse the config and every tool drops |
| Hand-edited `conf.d/10-dotfiles.toml` instead of `config.toml` | The next update overwrites it. Machine-local changes go in `config.toml` |
| Verified with `mise ls`'s exit code alone | Wholesale-disabled tools sail straight through |
| Ran `setup:codex` without `--skip-deps` | `settings.json` gets overwritten via `setup:claude` |
| Took `setup:skills` exiting 0 as proof the skills installed | A source that installed nothing looks exactly like one that worked |
| Replaced `permissions.allow` with the remote array | Every command this machine had allowed goes back to prompting |
| Reverted a local pin to `latest` because it "looked old" | Pins have reasons. Do not remove one without confirming |
| Dropped local divergence without asking or reporting | Nobody can work out why the machine broke |
| Forgot to update a revision file (dotfiles / skills) | The update notification fires every day despite being current |
