#!/usr/bin/env bash
# Tests that .mise.toml stays a facade over .dotfiles/setup/.
#
# The tasks in .mise.toml carry only a name, a description and dependencies;
# `setup:<name>` runs `<name>.sh`, which setup:scripts downloads to
# ~/.cache/dotfiles/setup/ before any task runs. Nothing in mise checks that
# the two halves agree, and both ways of breaking them are silent until a
# machine runs the setup:
#
#   1. a task added without its script — or without its name in the download
#      list — fails on a machine that has only the config, while a developer's
#      checkout still has the file and looks fine
#   2. shell creeping back into a task body, where ShellCheck, `bash -n` and
#      the tests below cannot reach it
#
# Run it by hand, or in CI:
#   bash tests/setup-facade-test.sh

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

# tomllib landed in Python 3.11 and macOS still ships 3.9, so fall back to uv —
# one of the tools this repo declares — rather than failing on a stock Mac.
if python3 -c 'import tomllib' 2>/dev/null; then
    py=(python3)
elif command -v uv >/dev/null 2>&1; then
    py=(uv run --quiet --python 3.12 python)
else
    echo "✗ needs Python 3.11+ (for tomllib) or uv on PATH"
    exit 1
fi

"${py[@]}" - "$repo" <<'PY'
import os
import re
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
config = tomllib.loads((repo / ".mise.toml").read_text())
tasks = config["tasks"]

LOADER = "setup:scripts"
SETUP_DIR = "$HOME/.cache/dotfiles/setup"

failures = 0


def fail(message):
    global failures
    failures += 1
    print(f"✗ {message}")


# --- 1. every task is a one-line delegation to its own script ---------------
delegating = {}
for name, task in tasks.items():
    if name in ("setup", LOADER):
        continue
    if not name.startswith("setup:"):
        fail(f"{name} is not a setup task; this test only knows about setup:*")
        continue
    script = name.removeprefix("setup:")
    delegating[name] = script
    run = task.get("run")
    expected = f"{SETUP_DIR}/{script}.sh"
    if run != expected:
        fail(f"{name} must run exactly {expected!r}, not {run!r}; the shell belongs in .dotfiles/setup/{script}.sh")
    if LOADER not in task.get("depends", []):
        fail(f"{name} does not depend on {LOADER}, so its script may not be there when it runs")
    if "shell" in task:
        fail(f"{name} sets `shell`, which a script with its own shebang does not need")

if "run" in tasks["setup"]:
    fail("the aggregate `setup` task must only declare depends")

# --- 2. the script each task names exists and is runnable -------------------
setup_dir = repo / ".dotfiles" / "setup"
present = {path.name.removesuffix(".sh") for path in setup_dir.glob("*.sh")}

for task_name, script in sorted(delegating.items()):
    path = setup_dir / f"{script}.sh"
    if not path.is_file():
        fail(f"{task_name} runs {script}.sh, which is not in .dotfiles/setup/")
        continue
    if not os.access(path, os.X_OK):
        fail(f".dotfiles/setup/{script}.sh is not executable; setup:scripts places it as 0755")
    first = path.read_text().splitlines()[0] if path.read_text() else ""
    if first != "#!/usr/bin/env bash":
        fail(f".dotfiles/setup/{script}.sh must start with `#!/usr/bin/env bash`, not {first!r}")

for orphan in sorted(present - set(delegating.values())):
    fail(f".dotfiles/setup/{orphan}.sh belongs to no task; every script is the body of one setup:<name>")

# --- 3. the loader downloads exactly those scripts --------------------------
loader = tasks[LOADER]["run"]

listed = re.search(r"^SCRIPTS=\(([^)]*)\)$", loader, re.MULTILINE)
if listed is None:
    fail(f"{LOADER} has no SCRIPTS=(...) list; this test cannot tell what it downloads")
else:
    downloaded = set(listed.group(1).split())
    for missing in sorted(set(delegating.values()) - downloaded):
        fail(f"{LOADER} never downloads {missing}.sh, so setup:{missing} would run a file that is not there")
    for extra in sorted(downloaded - set(delegating.values())):
        fail(f"{LOADER} downloads {extra}.sh, which belongs to no task")

if f'"$RAW_BASE/.dotfiles/setup/$name.sh"' not in loader:
    fail(f"{LOADER} must fetch each script from $RAW_BASE/.dotfiles/setup/, the path the repository publishes")

# A partially downloaded set must not run: the tasks that depend on the loader
# only stay behind it while it exits non-zero.
if not re.search(r"echo \"✗ \$failures setup script\(s\)[^\n]*\n\s*exit 1", loader):
    fail(f"{LOADER} must exit non-zero when a script fails to download")

if failures:
    print(f"\n{failures} failure(s)")
    sys.exit(1)

print(f"✓ {len(delegating)} setup tasks delegate to .dotfiles/setup/, all downloaded by {LOADER}")
PY
