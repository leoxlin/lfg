complete -c lfgwt -f

complete -c lfgwt -n '__fish_use_subcommand' -a 'add' -d 'create or switch to a worktree'
complete -c lfgwt -n '__fish_use_subcommand' -a 'cd' -d 'change to or create a worktree'
complete -c lfgwt -n '__fish_use_subcommand' -a 'list' -d 'list worktrees'
complete -c lfgwt -n '__fish_use_subcommand' -a 'ls' -d 'list worktrees'
complete -c lfgwt -n '__fish_use_subcommand' -a 'prune' -d 'remove stale worktrees'
complete -c lfgwt -n '__fish_use_subcommand' -a 'remove' -d 'remove a worktree'
complete -c lfgwt -n '__fish_use_subcommand' -a 'rm' -d 'remove a worktree'
complete -c lfgwt -n '__fish_use_subcommand' -a 'help' -d 'show usage'

complete -c lfgwt -n '__fish_seen_subcommand_from add cd remove rm' -a '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null)'
