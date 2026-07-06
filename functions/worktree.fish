# worktree Fish integration for lfg.
# Release version: 0.4.1 # x-release-please-version

function _worktree_usage
    echo "usage: worktree                                 (pick branch/worktree interactively)"
    echo "       worktree add <branch>                    (create or switch to a worktree)"
    echo "       worktree cd <branch>                     (change to or create a worktree)"
    echo "       worktree list|ls                         (list worktrees)"
    echo '       worktree prune                           (remove missing, older than ${LFG_PRUNE_OLDER_THAN_DAYS:-7}d, or without remote branch)'
    echo "       worktree remove|rm <branch>              (remove a worktree)"
    echo "       worktree help                            (show this help)"
end

function _worktree_require_git_repo
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo 'fatal: not a git repository (or any parent up to mount point /)' >&2
        return 1
    end
end

function _worktree_default_ref
    set -l default_ref (git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    if test -n "$default_ref"
        echo "$default_ref"
    else if git show-ref --verify --quiet refs/heads/main
        echo "main"
    else if git show-ref --verify --quiet refs/remotes/origin/main
        echo "origin/main"
    else if git show-ref --verify --quiet refs/heads/master
        echo "master"
    else if git show-ref --verify --quiet refs/remotes/origin/master
        echo "origin/master"
    else
        echo "HEAD"
    end
end

function _worktree_sources_dir
    if set -q LFG_SOURCE_DIR
        echo "$LFG_SOURCE_DIR"
    else
        echo "$HOME/src"
    end
end

function _worktree_base_dir
    echo "$(_worktree_sources_dir)/.agents/worktrees"
end

function _worktree_parent_path
    git worktree list --porcelain | awk 'NR==1 { sub(/^worktree /, ""); print }'
end

function _worktree_path_for_branch
    set -l branch $argv[1]
    git worktree list --porcelain | awk -v branch="$branch" '
        /^worktree / { path = $0; sub(/^worktree /, "", path) }
        /^branch / { ref = $0; sub(/^branch /, "", ref); if (ref == "refs/heads/" branch) { print path; exit } }
    '
end

function _worktree_new_path
    set -l branch $argv[1]
    set -l root (_worktree_parent_path)
    or return 1
    set -l repo (basename "$root")

    echo "$(_worktree_base_dir)/$repo-"(string replace -a '/' '-' -- "$branch")"/$repo"
end

function _worktree_branch_name
    set -l ref $argv[1]
    if test -z "$ref"
        echo "(detached)"
    else if string match -q 'refs/heads/*' -- "$ref"
        string replace 'refs/heads/' '' -- "$ref"
    else
        echo "$ref"
    end
end

function _worktree_branch_has_remote
    set -l branch $argv[1]

    if test -z "$branch"; or test "$branch" = "(detached)"
        return 1
    end

    set -l output (git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null)

    for remote_branch in $output
        if test (string replace -r '^[^/]+/' '' -- "$remote_branch") = "$branch"
            return 0
        end
    end

    return 1
end

function _worktree_is_older_than_days
    set -l worktree_path $argv[1]
    set -l days $argv[2]

    test -d "$worktree_path"
    or return 1

    set -l found (find "$worktree_path" -prune -mtime +"$days" -print 2>/dev/null)
    test -n "$found"
end

function _worktree_run_setup
    set -l worktree_path $argv[1]

    if functions -q lfg_worktree_setup
        lfg_worktree_setup "$worktree_path"
    end
end

function _worktree_cd
    set -l branch $argv[1]

    _worktree_require_branch "$branch"
    or return 1

    _worktree_add "$branch"
end

function _worktree_require_branch
    if test -n "$argv[1]"
        return 0
    end

    echo "You must provide a branch for worktree" >&2
    _worktree_usage >&2
    return 1
end

function _worktree_enter
    set -l worktree_path $argv[1]

    _worktree_run_setup "$worktree_path"
    or return 1
    cd "$worktree_path"
    or return 1
end

function _worktree_fzf
    if test (count $argv) -ne 2
        echo "_worktree_fzf requires a label and prompt" >&2
        return 2
    end

    set -l label $argv[1]
    set -l prompt $argv[2]
    set -l color bright-blue
    if set -q LFG_FZF_POINTER_COLOR
        set color $LFG_FZF_POINTER_COLOR
    end

    set -l opts "--color=pointer:$color"
    if set -q FZF_DEFAULT_OPTS
        set opts "$FZF_DEFAULT_OPTS $opts"
    end
    set -lx FZF_DEFAULT_OPTS "$opts"

    fzf --print-query --border=rounded --border-label="$label" --prompt="$prompt" --height=40% --reverse
end

function _worktree_pick_repo
    set -l sources_dir (_worktree_sources_dir)
    if not test -d "$sources_dir"
        echo "lfg: no source directory found at $sources_dir" >&2
        echo "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." >&2
        return 1
    end

    set -l repos (find "$sources_dir" -mindepth 1 -maxdepth 1 -type d \
        -exec test -e '{}/.git' ';' -print 2>/dev/null \
        | while read -l repo
            basename "$repo"
        end \
        | sort)
    if test (count $repos) -eq 0
        echo "lfg: no git repositories found under $sources_dir" >&2
        echo "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." >&2
        return 1
    end

    set -l out (printf '%s\n' $repos | _worktree_fzf ' Select a repo ' 'repo> ')
    set -l code $status
    if test $code -ne 0
        return 1
    end

    set -l repo_name (printf '%s\n' $out | tail -n1)
    if test -z "$repo_name"
        return 1
    end
    echo "$(_worktree_sources_dir)/$repo_name"
end

function _worktree_pick_branch
    set -l out (git worktree list --porcelain \
        | awk '/^branch / { sub("refs/heads/", "", $2); print $2 }' \
        | _worktree_fzf ' Select or create worktree branch ' 'worktree> ')
    set -l code $status

    # 0 = picked existing, 1 = no match (create new); anything else = aborted.
    if test $code -ne 0; and test $code -ne 1
        return 1
    end

    set -l branch (printf '%s\n' $out | tail -n1)
    if test -z "$branch"
        return 1
    end
    echo "$branch"
end

function _worktree_interactive_cd
    if not command -v fzf >/dev/null 2>&1
        echo "worktree: fzf is required for interactive mode" >&2
        return 1
    end

    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l repo
        _worktree_pick_repo | read -l repo
        or return 1
        cd "$repo"
        or return 1
    end

    set -l branch (_worktree_pick_branch)
    or return 1

    _worktree_add "$branch"
end

function _worktree_list_row
    set -l worktree_path $argv[1]
    set -l branch_ref $argv[2]
    set -l current_root $argv[3]

    if test -z "$worktree_path"
        return
    end

    set -l branch_name (_worktree_branch_name "$branch_ref")
    set -l marker " "
    if test "$worktree_path" = "$current_root"
        set marker "*"
    end
    printf "%s %s\t%s\n" "$marker" "$branch_name" "$worktree_path"
end

function _worktree_list
    _worktree_require_git_repo
    or return 1

    set -l current_root (git rev-parse --show-toplevel 2>/dev/null)
    or set current_root ""

    set -l worktree_path ""
    set -l branch_ref ""

    begin
        set -l lines (git worktree list --porcelain | string split \n)
        for line in $lines
            if test -z "$line"
                _worktree_list_row "$worktree_path" "$branch_ref" "$current_root"
                set worktree_path ""
                set branch_ref ""
            else if string match -q 'worktree *' -- "$line"
                set worktree_path (string replace 'worktree ' '' -- "$line")
            else if string match -q 'branch *' -- "$line"
                set branch_ref (string replace 'branch ' '' -- "$line")
            end
        end
        _worktree_list_row "$worktree_path" "$branch_ref" "$current_root"
    end | column -t -s \t
end

function _worktree_add
    set -l branch $argv[1]

    _worktree_require_branch "$branch"
    or return 1

    _worktree_require_git_repo
    or return 1

    set -l worktree_path (_worktree_path_for_branch "$branch")
    or return 1
    if test -n "$worktree_path"
        _worktree_enter "$worktree_path"
        return
    end

    set worktree_path (_worktree_new_path "$branch")
    or return 1
    mkdir -p (dirname "$worktree_path")
    or return 1

    if git show-ref --verify --quiet "refs/heads/$branch"
        git worktree add "$worktree_path" "$branch"
        or return 1
    else
        set -l default_ref (_worktree_default_ref)
        or return 1
        git worktree add -b "$branch" "$worktree_path" "$default_ref"
        or return 1
    end

    set worktree_path (_worktree_path_for_branch "$branch")
    or return 1
    if test -z "$worktree_path"
        echo "fatal: could not find worktree for branch '$branch'" >&2
        return 1
    end

    _worktree_enter "$worktree_path"
end

function _worktree_remove
    set -l branch $argv[1]

    _worktree_require_branch "$branch"
    or return 1

    _worktree_require_git_repo
    or return 1

    set -l parent (_worktree_parent_path)
    or return 1
    set -l worktree_path (_worktree_path_for_branch "$branch")
    or return 1
    if test -z "$worktree_path"
        echo "fatal: no worktree found for branch '$branch'" >&2
        return 1
    end

    git -C "$parent" worktree remove "$worktree_path"
    or return 1
    git -C "$parent" worktree prune
end

function _worktree_prune_days
    if set -q LFG_PRUNE_OLDER_THAN_DAYS
        echo $LFG_PRUNE_OLDER_THAN_DAYS
    else
        echo 7
    end
end

function _worktree_prune_reason
    set -l worktree_path $argv[1]
    set -l branch_name $argv[2]
    set -l days (_worktree_prune_days)

    if test ! -d "$worktree_path"
        echo "missing directory"
    else if _worktree_is_older_than_days "$worktree_path" "$days"
        echo "older than $days day(s)"
    else if not _worktree_branch_has_remote "$branch_name"
        echo "no remote branch"
    else
        return 1
    end
end

function _worktree_prune_record
    set -l parent $argv[1]
    set -l worktree_path $argv[2]
    set -l branch_ref $argv[3]

    if test -z "$worktree_path"; or test "$worktree_path" = "$parent"
        return 2
    end

    set -l branch_name (_worktree_branch_name "$branch_ref")
    set -l reason (_worktree_prune_reason "$worktree_path" "$branch_name")
    or return 2

    printf "Removing %s (%s)\t%s\n" "$branch_name" "$reason" "$worktree_path"
    if test ! -d "$worktree_path"
        return 0
    end

    git -C "$parent" worktree remove "$worktree_path"
end

function _worktree_prune
    _worktree_require_git_repo
    or return 1

    set -l parent (_worktree_parent_path)
    or return 1

    set -l worktree_path ""
    set -l branch_ref ""
    set -l removed 0
    set -l failed 0

    set -l lines (git -C "$parent" worktree list --porcelain | string split \n)
    for line in $lines
        if test -z "$line"
            _worktree_prune_record "$parent" "$worktree_path" "$branch_ref"
            set -l prune_status $status
            if test $prune_status -eq 0
                set removed 1
            else if test $prune_status -ne 2
                set failed 1
            end

            set worktree_path ""
            set branch_ref ""
        else if string match -q 'worktree *' -- "$line"
            set worktree_path (string replace 'worktree ' '' -- "$line")
        else if string match -q 'branch *' -- "$line"
            set branch_ref (string replace 'branch ' '' -- "$line")
        end
    end

    # Process the final record if there was no trailing blank line.
    _worktree_prune_record "$parent" "$worktree_path" "$branch_ref"
    set -l prune_status $status
    if test $prune_status -eq 0
        set removed 1
    else if test $prune_status -ne 2
        set failed 1
    end

    git -C "$parent" worktree prune
    or return 1

    if test $removed -eq 0; and test $failed -eq 0
        echo "No stale worktrees found."
    end

    return $failed
end

function worktree
    set -l command ""
    if set -q argv[1]
        set command $argv[1]
        set -e argv[1]
    end

    switch "$command"
        case add
            _worktree_add $argv
        case cd
            _worktree_cd $argv
        case list ls
            _worktree_list $argv
        case prune
            _worktree_prune $argv
        case remove rm
            _worktree_remove $argv
        case ""
            _worktree_interactive_cd
        case help -h --help
            _worktree_usage
        case '*'
            echo "unknown worktree command: $command" >&2
            _worktree_usage >&2
            return 1
    end
end

function wt --wraps worktree --description 'alias wt=worktree'
    worktree $argv
end
