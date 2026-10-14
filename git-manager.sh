#!/usr/bin/env bash

TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Not a Git repository!" >&2
    exit 1
fi

cd "$TARGET_DIR" || exit 1

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a Git repository!" >&2
    exit 1
fi

STARTING_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

check_clean_working_tree() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Error: Working tree has uncommitted changes. Cannot proceed with branch switching." >&2
        return 1
    fi
    return 0
}

restore_starting_branch() {
    if [ -n "$STARTING_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$STARTING_BRANCH"; then
        git switch -q "$STARTING_BRANCH" 2>/dev/null || true
    else
        git switch -q main 2>/dev/null || true
    fi
}

ask_yn() {
    local prompt="$1"
    local response
    read -r -p "$prompt [y/N]: " response
    case "$response" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

option_1_archive() {
    echo "Validate and Archive Branches"

    if ! check_clean_working_tree; then
        return 1
    fi

    for branch in $(git branch --format="%(refname:short)"); do
        if [ "$branch" = "main" ]; then
            continue
        fi

        prefix=$(echo "$branch" | cut -d'/' -f1)
        if [ "$prefix" = "feature" ] || [ "$prefix" = "bugfix" ] || [ "$prefix" = "hotfix" ] || [ "$prefix" = "archive" ]; then
            continue
        fi

        new_name="archive/$branch"

        if git branch -m "$branch" "$new_name" 2>/dev/null; then
            commit_date=$(git log -1 --format=%cs "$new_name")
            tag_archived="archived-$branch-$commit_date"
            git tag "$tag_archived" "$new_name" 2>/dev/null || true

            commit_count=$(git rev-list --count main.."$new_name")
            if [ "$commit_count" -gt 5 ]; then
                tag_milestone="milestone-$branch-$commit_count"
                git tag "$tag_milestone" "$new_name" 2>/dev/null || true
                echo "Renamed $branch to $new_name, created tags: $tag_archived, $tag_milestone"
            else
                echo "Renamed $branch to $new_name, created tag: $tag_archived"
            fi
        else
            echo "Error renaming $branch" >&2
        fi
    done

    restore_starting_branch
}

option_2_integrate() {
    echo "Integrate Feature Branches"

    if ! check_clean_working_tree; then
        return 1
    fi

    for branch in $(git branch --format="%(refname:short)"); do
        prefix=$(echo "$branch" | cut -d'/' -f1)
        if [ "$prefix" != "feature" ]; then
            continue
        fi

        ahead=$(git rev-list --count main.."$branch")
        if [ "$ahead" -eq 0 ]; then
            echo "$branch: nothing to integrate"
            continue
        fi

        if git merge-base --is-ancestor main "$branch"; then
            if ask_yn "Fast-forward main with $branch?"; then
                git switch -q main
                git merge --ff-only "$branch"
                hash=$(git rev-parse --short HEAD)
                msg=$(git log -1 --format=%s HEAD)
                echo "Integrated $branch via fast-forward. Main: $hash $msg"
            fi
        elif git merge-tree --write-tree main "$branch" >/dev/null 2>&1; then
            if ask_yn "Squash merge $branch into main?"; then
                git switch -q main
                git merge --squash "$branch"
                git commit -m "Squashed $branch"
                git branch -D "$branch" 2>/dev/null || true
                hash=$(git rev-parse --short HEAD)
                echo "Squash-merged $branch into main ($hash: Squashed $branch)"
            fi
        else
            echo "$branch conflicts with main"
        fi
    done

    restore_starting_branch
}

option_3_hygiene() {
    echo "Enforce Branch Hygiene"

    if ! check_clean_working_tree; then
        return 1
    fi

    for branch in $(git branch --format="%(refname:short)"); do
        if [ "$branch" = "main" ]; then
            continue
        fi

        prefix=$(echo "$branch" | cut -d'/' -f1)
        if [ "$prefix" = "feature" ] || [ "$prefix" = "bugfix" ] || [ "$prefix" = "hotfix" ] || [ "$prefix" = "archive" ]; then
            continue
        fi

        if [[ "$branch" =~ -v[0-9]+(\.[0-9]+)*$ ]]; then
            continue
        fi

        new_name="archive/$branch"

        if git branch -m "$branch" "$new_name" 2>/dev/null; then
            commit_date=$(git log -1 --format=%cs "$new_name")
            tag_archived="archived-$branch-$commit_date"
            git tag "$tag_archived" "$new_name" 2>/dev/null || true

            commit_count=$(git rev-list --count main.."$new_name")
            tag_milestone=""
            if [ "$commit_count" -gt 5 ]; then
                tag_milestone="milestone-$branch-$commit_count"
                git tag "$tag_milestone" "$new_name" 2>/dev/null || true
            fi

            squashed=false
            if ask_yn "Squash $new_name into single commit?"; then
                git switch -q "$new_name"
                root_commit=$(git rev-list --max-parents=0 HEAD)
                git reset --soft "$root_commit"
                git commit --amend --allow-empty -m "Squashed archive of $branch"
                squashed=true
            fi

            echo "Renamed $branch to $new_name, tags: $tag_archived $tag_milestone, squashed: $squashed"
        else
            echo "Error renaming $branch" >&2
        fi
    done

    restore_starting_branch
}

option_4_sync_rebase() {
    echo "Sync Report and Safe Rewrite"

    if ! check_clean_working_tree; then
        return 1
    fi

    for branch in $(git branch --format="%(refname:short)"); do
        prefix=$(echo "$branch" | cut -d'/' -f1)
        if [ "$prefix" != "feature" ]; then
            continue
        fi

        merge_base=$(git merge-base main "$branch")
        behind=$(git rev-list --count "$branch..main")
        ahead=$(git rev-list --count "main..$branch")

        if [ "$behind" -eq 0 ]; then
            echo "$branch is up to date (merge-base: $merge_base, ahead: $ahead, behind: 0)"
            continue
        fi

        echo "$branch: merge-base: $merge_base, ahead: $ahead, behind: $behind"

        if ask_yn "Rebase $branch onto main?"; then
            commit_date=$(git log -1 --format=%cs "$branch")
            backup_tag="backup-$branch-$commit_date"

            if git rev-parse "$backup_tag" >/dev/null 2>&1; then
                tag_commit=$(git rev-parse "$backup_tag^{commit}")
                branch_commit=$(git rev-parse "$branch")
                if [ "$tag_commit" = "$branch_commit" ]; then
                    echo "Backup tag $backup_tag exists at branch tip"
                else
                    echo "Error: backup tag $backup_tag exists on another commit" >&2
                    continue
                fi
            else
                git tag "$backup_tag" "$branch"
            fi

            old_base="$merge_base"

            if ! git rebase main "$branch" >/dev/null 2>&1; then
                git rebase --abort
                echo "$branch needs manual rebase"
                continue
            fi

            diff_out=$(git range-diff "$old_base..$backup_tag" "main..$branch")
            non_equals=$(echo "$diff_out" | grep -v '^=' | grep -v '^$' || true)

            if [ -z "$non_equals" ]; then
                count=$(git rev-list --count "$old_base..$backup_tag")
                verdict="all $count commits preserved"
            else
                verdict="changed review"
            fi

            echo "Rebased $branch. Backup: $backup_tag. Verdict: $verdict"
        fi
    done

    restore_starting_branch
}

show_menu() {
    echo ""
    echo "GIT MANAGER MENU"
    echo "1.Validate and Archive Branches"
    echo "2. Integrate Feature Branches"
    echo "3.Enforce Branch Hygiene"
    echo "4. Sync Report and Safe Rewrite"
    echo "5. Exit"
}

main_loop() {
    while true; do
        show_menu
        read -r -p "Select option: " choice
        case "$choice" in
            1) option_1_archive ;;
            2) option_2_integrate ;;
            3) option_3_hygiene ;;
            4) option_4_sync_rebase ;;
            5) restore_starting_branch; echo "Exiting."; exit 0 ;;
            *) echo "Invalid option" >&2 ;;
        esac
    done
}

main_loop
