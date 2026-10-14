# git-manager.sh — Branch Management Script

A Bash script that automates branch management in a **local** Git repository: archiving stale branches, integrating feature branches, enforcing naming hygiene, and safely rebasing branches that fell behind `main`. The script never talks to a remote (no fetch, pull, push or `git remote`).

## Requirements

- Git 2.38 or newer (`git switch`, `git range-diff`, `git merge-tree --write-tree`)
- Bash 4+ (on macOS: `brew install bash`; on Windows: Git Bash or WSL)
- LF line endings (check with `file git-manager.sh`)

## Files

| File | Purpose |
|---|---|
| `git-manager.sh` | the script |
| `README.md` | this file |
| `ai_usage.txt` | log of all AI interactions |

## Usage

```bash
chmod +x git-manager.sh
./git-manager.sh [repo_path]
```

- `repo_path` is optional and defaults to the current directory.
- More than one argument: a usage line is printed, exit code 1.
- Missing directory or not a Git repository: `Not a Git repository!`, exit code 1.
- All input (menu choices and Y/N answers) is read from standard input, so answers can be piped:

```bash
printf '1\n5\n' | ./git-manager.sh test_repo-test
```

### Menu

| # | Option | Summary |
|---|---|---|
| 1 | Validate and Archive Branches | renames branches without an allowed prefix to `archive/<name>`, creates `archived-…` and `milestone-…` tags |
| 2 | Integrate Feature Branches | fast-forwards or squash-merges `feature/*` into `main`, skips conflicting ones |
| 3 | Enforce Branch Hygiene | archives branches without a version suffix, optionally squashes them into one commit |
| 4 | Sync Report and Safe Rewrite | ahead/behind report, rebases lagging `feature/*` branches after creating a backup tag |
| 5 | Exit | exits with code 0 |

An invalid choice prints an error and shows the menu again. Y/N questions accept `Y` or `y` as yes; anything else is no. Options 2, 3 and 4 refuse to run with uncommitted changes. After every option the originally checked-out branch is checked out again (under its new name if it was renamed, or `main` if it was deleted).

## Building the test repository

Run the following script from the folder that contains `git-manager.sh`. It creates `test_repo/` (and deletes an existing one).

```bash
#!/usr/bin/env bash
set -e

rm -rf test_repo
mkdir -p test_repo
cd test_repo

git init -q -b main
git config user.name "Test User"
git config user.email "test@example.com"

app() {
    echo "$2" >> "$1"
    git add "$1"
    git commit -q -m "$3"
}

wr() {
    echo "$2" > "$1"
    git add "$1"
    git commit -q -m "$3"
}

for i in 1 2 3 4; do app file.txt "$i" "$i"; done

git switch -q -c feature/clean main
wr clean.txt "clean work" "feature/clean: add clean.txt"

git switch -q -c feature/behind main
wr history.txt "behind work" "feature/behind: work"

git switch -q main
app file.txt "main: update file.txt" "main: update file.txt"
wr conflict.txt "line 1" "main: add conflict.txt"
wr rebase.txt   "rebase base" "main: add rebase.txt"

git switch -q -c feature/conflict main
wr conflict.txt "line feature" "feature/conflict: change line"

git switch -q -c feature/conflict-rebase main
wr rebase.txt "feature rebase conflict" "feature/conflict-rebase: change rebase.txt"

git switch -q main
wr conflict.txt "line main" "main: change conflict.txt"
wr rebase.txt   "main rebase conflict" "main: change rebase.txt"

git switch -q -c bugfix/login main
wr history.txt "login fix" "bugfix/login: fix bug"

git switch -q -c old-experiment main
echo "experiment" >> history.txt
git add history.txt
GIT_AUTHOR_DATE="2025-03-15T12:00:00" GIT_COMMITTER_DATE="2025-03-15T12:00:00" \
    git commit -q -m "old-experiment: work"

git switch -q -c long-branch main
for i in {1..6}; do app history.txt "commit $i" "long-branch: commit $i"; done

git switch -q -c release-v1.2 main
wr history.txt "v1.2 release" "release-v1.2: bump version"

git switch -q -c some/bad/name main
wr history.txt "bad name edge case" "some/bad/name: work"

git switch -q -c already-archived main
wr history.txt "already archived work" "already-archived: work"

git switch -q -c archive/already-archived main
wr history.txt "pre-existing archive" "archive/already-archived: pre-created"

git switch -q -c feature/ff main
app file.txt "feature/ff step 1" "feature/ff: step 1"
app file.txt "feature/ff step 2" "feature/ff: step 2"

git switch -q main

echo "Repository ready at: $(pwd)"
git --no-pager branch
```

Every option rewrites refs, so always test on a copy:

```bash
cp -r test_repo test_repo-test
```

To start over, delete the copy and copy `test_repo` again.

### Sanity checks after building

```bash
cd test_repo
git merge-base --is-ancestor main feature/ff && echo "feature/ff can fast-forward"
git merge-tree --write-tree main feature/conflict >/dev/null; echo "exit code: $?"   # 1 = conflict
git rev-list --count main..long-branch                                               # 6
```

### Branches in the test repository

| Branch | Purpose |
|---|---|
| `main` | base history |
| `feature/ff` | can fast-forward into `main` |
| `feature/clean` | cannot fast-forward, merges without conflicts |
| `feature/behind` | behind `main`, rebases cleanly (option 4) |
| `feature/conflict` | conflicts with `main` (option 2) |
| `feature/conflict-rebase` | conflicts when rebased onto `main` (option 4) |
| `bugfix/login` | allowed prefix, must stay untouched |
| `old-experiment` | no prefix; commit dated 2025-03-15 (checks the date in the tag) |
| `long-branch` | no prefix, 6 commits ahead of `main` (milestone tag) |
| `release-v1.2` | version suffix (kept by option 3) |
| `some/bad/name` | `/` in the name (tag names keep the `/`) |
| `already-archived` | `archive/already-archived` already exists, so the rename must fail |

## Test scenario and session transcripts

Branches are processed in the order printed by `git for-each-ref --format='%(refname:short)' refs/heads/`. Run each scenario on a fresh copy (`rm -rf test_repo-test && cp -r test_repo test_repo-test`).

### Option 1 — Validate and Archive

```bash
printf '1\n5\n' | ./git-manager.sh test_repo-test
git -C test_repo-test branch
git -C test_repo-test tag
```

What to check:
- `already-archived`: the rename fails, an error goes to stderr, no tags are created, the script continues.
- `old-experiment` gets `archived-old-experiment-2025-03-15`.
- `long-branch` gets `archived-long-branch-<date>` and `milestone-long-branch-6`.
- `some/bad/name` gets `archived-some/bad/name-<date>`.
- Running option 1 a second time renames nothing and creates no duplicate tags.

```text
<paste the real session output here>
```

### Option 2 — Integrate Feature Branches

```bash
# n to the first two questions, so that feature/ff is still a fast-forward when it is reached
printf '2\nn\nn\ny\n5\n' | ./git-manager.sh test_repo-test
```

What to check:
- `feature/ff` is a fast-forward (`--ff-only`), the branch stays.
- `feature/behind` and `feature/clean` merge cleanly and are offered as squash (`Squashed <branch>`, branch deleted with `-D`).
- `feature/conflict` and `feature/conflict-rebase` are reported as conflicts with `main`; `main` and the working tree are untouched.
- If you answer `y` to the squash of `feature/behind` or `feature/clean`, `main` moves and `feature/ff` is no longer a fast-forward, because every check is made against `main` as it is at that moment.

```text
<paste the real session output here>
```

### Option 3 — Enforce Branch Hygiene

```bash
printf '3\ny\nn\ny\ny\n5\n' | ./git-manager.sh test_repo-test
git -C test_repo-test log --oneline archive/old-experiment
```

What to check:
- `release-v1.2` is kept (it has a version suffix); `bugfix/login`, `feature/*` and `main` are ignored.
- Renamed branches get the same tags as in option 1; tags are created before the squash.
- On `y`, the branch ends up with exactly one parentless commit: `Squashed archive of <original-name>`.

```text
<paste the real session output here>
```

### Option 4 — Sync Report and Safe Rewrite

```bash
printf '4\ny\ny\ny\ny\n5\n' | ./git-manager.sh test_repo-test
git -C test_repo-test tag | grep backup
```

What to check:
- Each `feature/*` branch gets a report with merge base, ahead and behind counts.
- `feature/ff` is up to date (not behind).
- `feature/behind` and `feature/clean`: backup tag `backup-<branch>-<date>` is created, rebase succeeds, range-diff verdict is `all 1 commits preserved`.
- `feature/conflict` and `feature/conflict-rebase`: the rebase is aborted, the branch is marked `needs manual rebase`, the backup tag stays.
- A second run reuses a backup tag that points at the branch tip and says so; a backup tag pointing at another commit gives `backup tag exists` and the branch is skipped.

```text
<paste the real session output here>
```

### General checks

```bash
./git-manager.sh a b; echo "exit: $?"                    # usage, exit 1
./git-manager.sh /no/such/dir; echo "exit: $?"           # Not a Git repository!, exit 1
printf 'help\n5\n' | ./git-manager.sh test_repo-test     # error, menu again, exit
printf '1\n' | ./git-manager.sh test_repo-test           # ends on EOF, no endless loop
grep -nE 'fetch|pull|push|remote' git-manager.sh         # no output expected
file git-manager.sh                                      # no "CRLF"
```

## Problems I hit and how I solved them

- **Two commands glued onto one line in the build script.** A missing newline turned `git switch -q main` into extra arguments of `wr`, so later commits landed on the wrong branch and the conflict scenarios disappeared. Fixed the newline and added sanity checks (`merge-base --is-ancestor`, `merge-tree`, `rev-list --count`).
- **`feature/ff` stopped being a fast-forward.** It was created before `main` moved on. It is now created last, from the final `main`.
- **Re-running the build script failed.** `git switch -c` fails on an existing branch under `set -e`. The script now starts with `rm -rf test_repo`.
- **Infinite menu loop on end of input.** `read` fails on EOF but the loop kept going. The menu now exits when `read` fails, and `ask_yn` treats EOF as "no".
- **No prompt with piped input.** `read -p` prints the prompt only when stdin is a terminal, so prompts were missing in piped sessions. Prompts are printed with `printf`.
- **Y/N too permissive.** `[Yy]*` accepted `yes` or `yolo`; only exactly `Y` or `y` means yes now.
- **Wrong range-diff verdict.** `grep -v '^='` never matched, because the `=` marker is in the third column of a range-diff line, so the verdict was always "changed". The verdict now looks at the marker column.
- **Typos that broke option 4.** `if !check_clean_working_tree` (missing space), `diff_out=(...)` (array instead of command substitution), `verdict"..."` (missing `=`), an inverted `if git rebase` (abort ran on success), and a missing `>` in `git rev-parse "$backup_tag" /dev/null`.
- **Backup tag check was ambiguous.** `git rev-parse <name>` resolves branches and hashes too. Now `git rev-parse --verify --quiet "refs/tags/<name>"` is used.
- **`|| true` hid tag errors and the report lied.** Tags are created through a helper that skips existing tags and reports only tags actually created, so re-runs create no duplicates.
- **Branch list and loop.** A `while read` loop over `git for-each-ref` would let the Y/N questions swallow branch names. The list is read into a variable first and processed with `for branch in $list`.
