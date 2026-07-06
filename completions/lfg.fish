# Release version: 0.1.0 # x-release-please-version

complete -c lfg -f

complete -c lfg -n '__fish_is_first_token' -a 'claude' -d 'launch claude'
complete -c lfg -n '__fish_is_first_token' -a 'claude-code' -d 'launch claude-code'
complete -c lfg -n '__fish_is_first_token' -a 'codex' -d 'launch codex'
complete -c lfg -n '__fish_is_first_token' -a 'aider' -d 'launch aider'
complete -c lfg -n '__fish_is_first_token' -a 'gemini' -d 'launch gemini'

complete -c lfg -n '__fish_seen_subcommand_from claude claude-code codex aider gemini' -a '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null)'
