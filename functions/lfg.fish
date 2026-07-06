# lfg: jump into a worktree and start an agent.
# Release version: 0.1.0 # x-release-please-version
#
# Usage: lfg [entrypoint] [branch_name]
#
# - entrypoint: the command to run once inside the worktree (default: claude).
#     lfg               -> claude in a picked branch
#     lfg codex         -> codex in a picked branch
#     lfg claude feat/x -> claude in worktree for branch feat/x
#     lfg update        -> download and install the latest lfg release
# - Outside a git repo: pick one from $LFG_SOURCE_DIR via fzf (type to filter).
# - With no branch: pick an existing worktree branch, or type a new name to
#   create one.
# - Creates/switches the worktree (under $LFG_SOURCE_DIR/.agents/worktrees, via
#   the worktree helper) and launches the entrypoint there. LFG_SOURCE_DIR
#   defaults to ~/src if unset.

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
    if set -q LFG_INSTALL_DIR
        set install_dir "$LFG_INSTALL_DIR"
    end

    set -l release_version latest
    if set -q LFG_RELEASE_VERSION
        set release_version "$LFG_RELEASE_VERSION"
    end

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

    env \
        INSTALL_SHELL=fish \
        LFG_INSTALL_DIR="$install_dir" \
        LFG_RELEASE_VERSION="$release_version" \
        bash "$install_script"
    set -l update_status $status

    rm -f "$install_script"
    return $update_status
end

function lfg
    if set -q argv[1]; and test "$argv[1]" = update
        _lfg_update
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
    if set -q argv[2]
        set branch $argv[2]
    end

    if not command -v "$entrypoint" >/dev/null 2>&1
        echo "lfg: entrypoint not found on PATH: $entrypoint" >&2
        return 1
    end

    # Already in a worktree with no branch requested: just launch here.
    if test -z "$branch"; and _lfg_in_worktree
        "$entrypoint"
        return
    end

    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l repo (_worktree_pick_repo)
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
