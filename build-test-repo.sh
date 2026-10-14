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

echo "Репозиторій готовий в: $(pwd)"
git --no-pager branch
