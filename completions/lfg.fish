# Fish completions for lfg.
# Release version: 0.4.0 # x-release-please-version

set -g __lfg_completion_dir (status dirname)

complete -c lfg -f

complete -c lfg -n '__fish_is_first_token' -a '--update' -d 'update the lfg plugin to latest'
complete -c lfg -n '__fish_is_first_token' -a '--help' -d 'show lfg usage'

function __lfg_completions_file
    if set -q LFG_COMPLETIONS_FILE
        echo "$LFG_COMPLETIONS_FILE"
    else if set -q __lfg_completion_dir
        echo "$__lfg_completion_dir/lfg.entrypoints"
    end
end

function __lfg_file_entrypoint_completions
    set -l completions_file (__lfg_completions_file)

    if test -z "$completions_file"
        return 1
    end

    if not test -r "$completions_file"
        return 1
    end

    awk 'NF && $1 !~ /^#/ { print $1 }' "$completions_file"
end

function __lfg_entrypoint_completions
    __lfg_file_entrypoint_completions
end

complete -c lfg -n '__fish_is_first_token' -a '(__lfg_entrypoint_completions)' -d 'launch agent in selected worktree'
