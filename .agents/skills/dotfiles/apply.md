# /dotfiles apply — apply an available update to this machine

`install.sh` and `mise run setup` are written to **overwrite local state with the
remote's**. Per-machine circumstances — pinned versions, tools only this box needs,
hand-added hooks — do not exist in the repository, so a plain re-run deletes them
silently.

The job here is to **separate "changes to take" from "local divergence to keep"
before anything is overwritten**. Running `install.sh` without reading a diff first
defeats the entire point.

## Overwrite hazards

What a plain re-run does. This is the whole picture the decisions hang off.

| Target | A plain re-run | Handling |
|---|---|---|
| `~/.config/mise/config.toml` | **Wholesale curl overwrite** from the repo's `.mise.toml` | **3-way merge** (step 4). The biggest hazard |
| `~/.claude/settings.json` | Deep merge via `jq -s '.[0] * .[1]'`, **remote wins on conflicts**; arrays (`permissions.allow` etc.) are **replaced, not concatenated** | **Apply by hand** (step 5). Leave it alone when the repo has no diff |
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
git -C "$REPO" show "$INSTALLED:.mise.toml"           | diff - ~/.config/mise/config.toml
git -C "$REPO" show "$INSTALLED:.claude/statusline.sh" | diff - ~/.claude/statusline.sh
```

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
```

### 4. 3-way merge the mise config

Never curl over it. Put working files in a scratch directory (`$W`).

```bash
git -C "$REPO" show "$INSTALLED:.mise.toml" > "$W/base"     # common ancestor
git -C "$REPO" show  "origin/main:.mise.toml" > "$W/theirs" # newer repository side
cp ~/.config/mise/config.toml                  "$W/ours"    # this machine
git merge-file -p "$W/ours" "$W/base" "$W/theirs" > "$W/merged"
```

Conflicts are marked with `<<<<<<<`. **Never install a file with markers left in** —
mise will fail to read the config. Resolve each one on its meaning:

- Local pins a version, repository says `latest` → confirm why it is pinned; keep the pin if the reason still holds
- Repository adds a tool or a `depends` entry → take it
- Local changed `[settings]` (e.g. `experimental = true`) → keep local
- Repository removed a tool → keep it if this machine uses it; otherwise follow the removal

**Absent markers do not mean nothing was lost.** Diff both ways to confirm the merge did
what you intended:

```bash
diff "$W/ours" "$W/merged"    # did the repository's changes land?
diff "$W/theirs" "$W/merged"  # did the local divergence survive?
```

Then install it and **verify the content, not just the parse**. `mise ls` exiting 0
proves very little.

```bash
mise ls --installed | awk '{print $1}' | sort > "$W/tools.before"   # capture before installing
cp "$W/merged" ~/.config/mise/config.toml
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
appears at runtime. **This is often a pre-existing repository bug rather than something
the merge caused** — do not patch it locally; report it upstream with `/dotfiles pr`.

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

If it was modified locally, 3-way merge it exactly like the mise config.

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
| Ran `install.sh` before reading a diff | The local mise config is already gone. Restore from backup and start over |
| Ignored a failing `ghq get` / `fetch` | You are judging against a stale `origin/main` |
| Kept 3-way merging without a base | `bad object`. Suspect a force-push and switch to no-base mode |
| Judged local divergence against current `main` | Repository updates get discarded as local edits |
| Installed a file with conflict markers | mise cannot parse the config and every tool drops |
| Verified with `mise ls`'s exit code alone | Wholesale-disabled tools sail straight through |
| Ran `setup:codex` without `--skip-deps` | `settings.json` gets overwritten via `setup:claude` |
| Took `setup:skills` exiting 0 as proof the skills installed | A source that installed nothing looks exactly like one that worked |
| Replaced `permissions.allow` with the remote array | Every command this machine had allowed goes back to prompting |
| Reverted a local pin to `latest` because it "looked old" | Pins have reasons. Do not remove one without confirming |
| Dropped local divergence without asking or reporting | Nobody can work out why the machine broke |
| Forgot to update a revision file (dotfiles / skills) | The update notification fires every day despite being current |
