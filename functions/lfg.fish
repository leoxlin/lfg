# lfg Fish integration.
# Release version: 0.2.0 # x-release-please-version

# Load the worktree helpers (also defines the worktree command).
set -l __lfg_dir (status dirname)
source "$__lfg_dir/worktree.fish"

function _lfg_in_worktree
    set -l git_dir (git rev-parse --absolute-git-dir 2>/dev/null)
    or return 1
    set -l common_dir (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    or return 1

    test "$git_dir" != "$common_dir"
end

function _lfg_update
    if not command -v curl >/dev/null 2>&1
        echo "lfg: curl is required to update" >&2
        return 1
    end

    set -l install_url https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh

    set -l install_dir "$HOME/.config/lfg"

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

function _lfg_usage
    echo "usage: lfg [entrypoint]     (navigate to a worktree and start entrypoint, e.g. codex)"
    echo "       lfg --update         (update the lfg plugin to latest)"
    echo "       lfg --help           (show this help)"
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

    if set -q argv[1]; and test "$argv[1]" = --help
        _lfg_usage
        return
    end

    set -l entrypoint
    if set -q argv[1]
        set entrypoint $argv[1]
    else if set -q LFG_DEFAULT_AGENT_COMMAND
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
