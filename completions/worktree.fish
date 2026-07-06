# Fish completions for worktree.
# Release version: 0.4.0 # x-release-please-version

complete -c worktree -f

complete -c worktree -n '__fish_use_subcommand' -a 'add' -d 'create or switch to a worktree'
complete -c worktree -n '__fish_use_subcommand' -a 'cd' -d 'change to or create a worktree'
complete -c worktree -n '__fish_use_subcommand' -a 'list' -d 'list worktrees'
complete -c worktree -n '__fish_use_subcommand' -a 'ls' -d 'list worktrees'
complete -c worktree -n '__fish_use_subcommand' -a 'prune' -d 'remove missing, older-than-LFG_PRUNE_OLDER_THAN_DAYS, or without remote branch'
complete -c worktree -n '__fish_use_subcommand' -a 'remove' -d 'remove a worktree'
complete -c worktree -n '__fish_use_subcommand' -a 'rm' -d 'remove a worktree'
complete -c worktree -n '__fish_use_subcommand' -a 'help' -d 'show worktree usage'

complete -c worktree -n '__fish_seen_subcommand_from add cd remove rm' -a '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null)'

complete -c wt -w worktree
