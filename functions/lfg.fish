# lfg Fish integration.
# Release version: 0.6.0 # x-release-please-version

# Load the worktree helpers (also defines the worktree command).
set -g __lfg_dir (status dirname)
source "$__lfg_dir/worktree.fish"

function _lfg_in_worktree
    set -l git_dir (git rev-parse --git-dir 2>/dev/null)
    or return 1
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null)
    or return 1

    test "$git_dir" != "$common_dir"
end

function _lfg_update
    if not command -v curl >/dev/null 2>&1
        echo "lfg: curl is required to update" >&2
        return 1
    end

    set -l install_url https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh

    # Compute the install directory the same way _lfg_version does, resolving
    # any symlink so custom install directories are preserved across updates.
    set -l script_path (status filename)
    if test -L "$script_path"
        set script_path (readlink "$script_path")
    end
    set -l install_dir (dirname (dirname "$script_path"))

    set -l tmpdir /tmp
    if set -q TMPDIR
        set tmpdir "$TMPDIR"
    end

    set -l install_script (mktemp "$tmpdir/lfg-install.XXXXXX")
    or return 1

    if not curl -fsSL "$install_url" -o "$install_script"
        rm -f "$install_script"
        return 1
    end

    bash "$install_script" --install-shell fish --install-dir "$install_dir"
    set -l update_status $status

    rm -f "$install_script"
    return $update_status
end

function _lfg_version
    set -l script_path (status filename)
    if test -L "$script_path"
        set script_path (readlink "$script_path")
    end
    set -l install_dir (dirname (dirname "$script_path"))

    set -l version_file "$install_dir/VERSION"
    set -l installed_version unknown

    if test -r "$version_file"
        set installed_version (cat "$version_file")
    end

    echo "lfg $installed_version"
end

function _lfg_usage
    echo "usage: lfg [entrypoint]     (navigate to a worktree and start entrypoint, e.g. codex)"
    echo "       lfg --update         (update the lfg plugin to latest)"
    echo "       lfg --version        (show the installed lfg version)"
    echo "       lfg --help           (show this help)"
end

function _lfg_completions_file
    if set -q LFG_COMPLETIONS_FILE
        echo "$LFG_COMPLETIONS_FILE"
        return
    end

    # Resolve symlinks like _lfg_version so custom install directories keep
    # finding the bundled completions file.
    set -l script_path (status filename)
    if test -L "$script_path"
        set script_path (readlink "$script_path")
    end
    set -l install_dir (dirname (dirname "$script_path"))

    echo "$install_dir/completions/lfg.entrypoints"
end

function _lfg_entrypoint_completions
    set -l completions_file (_lfg_completions_file)

    if test -z "$completions_file"
        return 1
    end

    if not test -r "$completions_file"
        return 1
    end

    awk 'NF && $1 !~ /^#/ { print $1 }' "$completions_file"
end

function _lfg_smart_mode
    set -q LFG_SMART_MODE; and test -n "$LFG_SMART_MODE"
end

function _lfg_available_entrypoints
    for entrypoint in (_lfg_entrypoint_completions)
        if command -v "$entrypoint" >/dev/null 2>&1
            echo "$entrypoint"
        end
    end
end

function _lfg_pick_entrypoint
    set -l entrypoints (_lfg_available_entrypoints | _worktree_recency_sort entrypoint "")
    if test (count $entrypoints) -eq 0
        echo "lfg: no available agent entrypoints found on PATH" >&2
        return 1
    end

    if not command -v fzf >/dev/null 2>&1
        echo "lfg: fzf is required to pick an entrypoint" >&2
        return 1
    end

    set -l out (printf '%s\n' $entrypoints | _worktree_fzf ' Select an agent ' 'agent> ')
    set -l code $status
    if test $code -ne 0
        return 1
    end

    set -l entrypoint (printf '%s\n' $out | tail -n1)
    if test -z "$entrypoint"
        return 1
    end
    _worktree_recency_record entrypoint "" "$entrypoint"
    echo "$entrypoint"
end

function lfg
    if test (count $argv) -gt 1
        _lfg_usage >&2
        return 1
    end

    if set -q argv[1]; and test "$argv[1]" = --update
        _lfg_update
        return
    end

    if set -q argv[1]; and test "$argv[1]" = --version
        _lfg_version
        return
    end

    if set -q argv[1]; and test "$argv[1]" = --help
        _lfg_usage
        return
    end

    set -l entrypoint
    if test (count $argv) -eq 0; and _lfg_smart_mode
        # Pipe instead of command substitution so picker errors reach stderr.
        # `read -l` inside an `if` block is block-scoped, so stage the value
        # in a block-local variable before assigning the function-local one.
        set -l picked_entrypoint
        _lfg_pick_entrypoint | read -l picked_entrypoint
        or return 1
        set entrypoint $picked_entrypoint
    else if set -q argv[1]
        set entrypoint $argv[1]
    else if test -n "$LFG_DEFAULT_AGENT_COMMAND"
        set entrypoint $LFG_DEFAULT_AGENT_COMMAND
    else
        set entrypoint claude
    end

    set -l branch

    if not command -v "$entrypoint" >/dev/null 2>&1
        echo "lfg: entrypoint not found on PATH: $entrypoint" >&2
        return 1
    end

    # Already in a worktree: just launch here.
    if test -z "$branch"; and _lfg_in_worktree
        "$entrypoint"
        return
    end

    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l repo
        _worktree_pick_repo | read -l repo
        or return 1
        cd "$repo"
        or return 1
    end

    if test -z "$branch"
        set branch (_worktree_pick_branch)
        or return 1
    end

    _worktree_add "$branch"
    or return 1

    "$entrypoint"
end
