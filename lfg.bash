# lfg Bash integration.
# Release version: 0.2.0 # x-release-please-version

__lfg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function _worktree_usage() {
  echo "usage: worktree                                 (pick branch/worktree interactively)"
  echo "       worktree add <branch>                    (create or switch to a worktree)"
  echo "       worktree cd <branch>                     (change to or create a worktree)"
  echo "       worktree list|ls                         (list worktrees)"
  echo '       worktree prune                           (remove missing, older than ${LFG_PRUNE_OLDER_THAN_DAYS:-7}d, or without remote branch)'
  echo "       worktree remove|rm <branch>              (remove a worktree)"
  echo "       worktree help                            (show this help)"
}

function _worktree_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo 'fatal: not a git repository (or any parent up to mount point /)' >&2
    return 1
  fi
}

function _worktree_default_ref() {
  local default_ref

  default_ref="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$default_ref" ]; then
    echo "$default_ref"
  elif git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "origin/main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "origin/master"
  else
    echo "HEAD"
  fi
}

function _worktree_sources_dir() {
  local sources_dir="${LFG_SOURCE_DIR:-$HOME/src}"
  echo "${sources_dir}"
}

function _worktree_base_dir() {
  echo "$(_worktree_sources_dir)/.agents/worktrees"
}

function _worktree_parent_path() {
  git worktree list --porcelain | awk 'NR==1 { sub(/^worktree /, ""); print }'
}

function _worktree_path_for_branch() {
  local branch="$1"

  git worktree list --porcelain | awk -v branch="$branch" '
    /^worktree / { path = $0; sub(/^worktree /, "", path) }
    /^branch / { ref = $0; sub(/^branch /, "", ref); if (ref == "refs/heads/" branch) { print path; exit } }
  '
}

function _worktree_new_path() {
  local branch root repo

  branch="$1"
  root="$(_worktree_parent_path)" || return 1
  repo="$(basename "$root")"

  echo "$(_worktree_base_dir)/$repo-${branch//\//-}/$repo"
}

function _worktree_branch_name() {
  local ref

  ref="$1"
  if [ -z "$ref" ]; then
    echo "(detached)"
  elif [[ "$ref" == refs/heads/* ]]; then
    echo "${ref#refs/heads/}"
  else
    echo "$ref"
  fi
}

function _worktree_branch_has_remote() {
  local branch="$1"
  local remote_branch output

  if [ -z "$branch" ] || [ "$branch" = "(detached)" ]; then
    return 1
  fi

  output="$(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null)"

  while IFS= read -r remote_branch; do
    [ -n "$remote_branch" ] || continue
    if [ "${remote_branch#*/}" = "$branch" ]; then
      return 0
    fi
  done <<< "$output"

  return 1
}

function _worktree_is_older_than_days() {
  local worktree_path days

  worktree_path="$1"
  days="$2"

  [ -d "$worktree_path" ] || return 1
  [ -n "$(find "$worktree_path" -prune -mtime +"$days" -print 2>/dev/null)" ]
}

function _worktree_prune_days() {
  echo "${LFG_PRUNE_OLDER_THAN_DAYS:-7}"
}

function _worktree_prune_reason() {
  local worktree_path="$1"
  local branch_name="$2"
  local days="$(_worktree_prune_days)"

  if [ ! -d "$worktree_path" ]; then
    echo "missing directory"
  elif _worktree_is_older_than_days "$worktree_path" "$days"; then
    echo "older than $days day(s)"
  elif ! _worktree_branch_has_remote "$branch_name"; then
    echo "no remote branch"
  else
    return 1
  fi
}

function _worktree_prune_record() {
  local parent="$1"
  local worktree_path="$2"
  local branch_ref="$3"
  local branch_name reason

  [ -n "$worktree_path" ] || return 2
  [ "$worktree_path" != "$parent" ] || return 2

  branch_name="$(_worktree_branch_name "$branch_ref")"
  reason="$(_worktree_prune_reason "$worktree_path" "$branch_name")" || return 2

  printf "Removing %s (%s)\t%s\n" "$branch_name" "$reason" "$worktree_path"
  [ -d "$worktree_path" ] || return 0

  git -C "$parent" worktree remove "$worktree_path"
}

function _worktree_run_setup() {
  local worktree_path="$1"

  if declare -F lfg_worktree_setup >/dev/null 2>&1; then
    lfg_worktree_setup "$worktree_path"
  fi
}

function _worktree_cd() {
  local branch="$1"

  _worktree_require_branch "$branch" || return 1

  _worktree_add "$branch"
}

function _worktree_require_branch() {
  if [ -n "$1" ]; then
    return 0
  fi

  echo "You must provide a branch for worktree" >&2
  _worktree_usage >&2
  return 1
}

function _worktree_enter() {
  local worktree_path="$1"

  _worktree_run_setup "$worktree_path" || return 1
  cd "$worktree_path" || return 1
}

function _worktree_fzf() {
  if [ "$#" -ne 2 ]; then
    echo "_worktree_fzf requires a label and prompt" >&2
    return 2
  fi

  local label="$1"
  local prompt="$2"
  local color="${LFG_FZF_POINTER_COLOR:-bright-blue}"
  local opts="--color=pointer:${color}"

  if [ -n "${FZF_DEFAULT_OPTS:-}" ]; then
    opts="${FZF_DEFAULT_OPTS} ${opts}"
  fi

  FZF_DEFAULT_OPTS="$opts" fzf --print-query --border=rounded --border-label="$label" --prompt="$prompt" --height=40% --reverse
}

function _worktree_pick_repo() {
  local sources_dir repos out code repo_name

  sources_dir="$(_worktree_sources_dir)"
  if [ ! -d "$sources_dir" ]; then
    echo "lfg: no source directory found at $sources_dir" >&2
    echo "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." >&2
    return 1
  fi

  repos="$(find "$sources_dir" -mindepth 1 -maxdepth 1 -type d \
      -exec test -e '{}/.git' ';' -print 2>/dev/null \
    | while IFS= read -r repo; do basename "$repo"; done \
    | sort)"
  if [ -z "$repos" ]; then
    echo "lfg: no git repositories found under $sources_dir" >&2
    echo "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." >&2
    return 1
  fi

  out="$(printf '%s\n' "$repos" | _worktree_fzf ' Select a repo ' 'repo> ')"
  code=$?
  [ "$code" -eq 0 ] || return 1

  repo_name="$(printf '%s\n' "$out" | tail -n1)"
  [ -n "$repo_name" ] || return 1
  echo "$(_worktree_sources_dir)/$repo_name"
}

function _worktree_pick_branch() {
  local out code branch

  out="$(git worktree list --porcelain \
    | awk '/^branch / { sub("refs/heads/", "", $2); print $2 }' \
    | _worktree_fzf ' Select or create worktree branch ' 'worktree> ')"
  code=$?

  # 0 = picked existing, 1 = no match (create new); anything else = aborted.
  [ "$code" -eq 0 ] || [ "$code" -eq 1 ] || return 1

  branch="$(printf '%s\n' "$out" | tail -n1)"
  [ -n "$branch" ] || return 1
  echo "$branch"
}

function _worktree_interactive_cd() {
  local repo branch

  if ! command -v fzf >/dev/null 2>&1; then
    echo "worktree: fzf is required for interactive mode" >&2
    return 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo="$(_worktree_pick_repo)" || return 1
    cd "$repo" || return 1
  fi

  branch="$(_worktree_pick_branch)" || return 1

  _worktree_add "$branch"
}

function _worktree_list() {
  local current_root worktree_path branch_ref branch_name marker line

  _worktree_require_git_repo || return 1

  current_root="$(git rev-parse --show-toplevel 2>/dev/null)" || current_root=""
  worktree_path=""
  branch_ref=""

  _worktree_list_row() {
    [ -n "$worktree_path" ] || return
    branch_name="$(_worktree_branch_name "$branch_ref")"
    if [ "$worktree_path" = "$current_root" ]; then
      marker="*"
    else
      marker=" "
    fi
    printf "%s %s\t%s\n" "$marker" "$branch_name" "$worktree_path"
  }

  {
    while IFS= read -r line; do
      if [ -z "$line" ]; then
        _worktree_list_row
        worktree_path=""
        branch_ref=""
      elif [[ "$line" == worktree\ * ]]; then
        worktree_path="${line#worktree }"
      elif [[ "$line" == branch\ * ]]; then
        branch_ref="${line#branch }"
      fi
    done < <(git worktree list --porcelain)
    _worktree_list_row
  } | column -t -s $'\t'

  unset -f _worktree_list_row
}

function _worktree_add() {
  local branch worktree_path default_ref

  branch="$1"
  _worktree_require_branch "$branch" || return 1

  _worktree_require_git_repo || return 1

  worktree_path="$(_worktree_path_for_branch "$branch")" || return 1
  if [ -n "$worktree_path" ]; then
    _worktree_enter "$worktree_path"
    return
  fi

  worktree_path="$(_worktree_new_path "$branch")" || return 1
  mkdir -p "$(dirname "$worktree_path")" || return 1

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$worktree_path" "$branch" || return 1
  else
    default_ref="$(_worktree_default_ref)" || return 1
    git worktree add -b "$branch" "$worktree_path" "$default_ref" || return 1
  fi

  worktree_path="$(_worktree_path_for_branch "$branch")" || return 1
  if [ -z "$worktree_path" ]; then
    echo "fatal: could not find worktree for branch '$branch'" >&2
    return 1
  fi

  _worktree_enter "$worktree_path"
}

function _worktree_remove() {
  local branch parent worktree_path

  branch="$1"
  _worktree_require_branch "$branch" || return 1

  _worktree_require_git_repo || return 1

  parent="$(_worktree_parent_path)" || return 1
  worktree_path="$(_worktree_path_for_branch "$branch")" || return 1
  if [ -z "$worktree_path" ]; then
    echo "fatal: no worktree found for branch '$branch'" >&2
    return 1
  fi

  git -C "$parent" worktree remove "$worktree_path" || return 1
  git -C "$parent" worktree prune
}

function _worktree_prune() {
  local parent worktree_path branch_ref line removed failed

  _worktree_require_git_repo || return 1

  parent="$(_worktree_parent_path)" || return 1

  worktree_path=""
  branch_ref=""
  removed=0
  failed=0

  _worktree_prune_process() {
    _worktree_prune_record "$parent" "$worktree_path" "$branch_ref"
    case "$?" in
      0) removed=1 ;;
      2) ;;
      *) failed=1 ;;
    esac
  }

  while IFS= read -r line; do
    if [ -z "$line" ]; then
      _worktree_prune_process "$worktree_path" "$branch_ref"
      worktree_path=""
      branch_ref=""
    elif [[ "$line" == worktree\ * ]]; then
      worktree_path="${line#worktree }"
    elif [[ "$line" == branch\ * ]]; then
      branch_ref="${line#branch }"
    fi
  done < <(git -C "$parent" worktree list --porcelain)

  _worktree_prune_process "$worktree_path" "$branch_ref"

  unset -f _worktree_prune_process

  git -C "$parent" worktree prune || return 1
  if [ "$removed" -eq 0 ] && [ "$failed" -eq 0 ]; then
    echo "No stale worktrees found."
  fi

  return "$failed"
}

function worktree() {
  local command

  if [ $# -gt 0 ]; then
    command="$1"
    shift
  else
    command=""
  fi

  case "$command" in
    add)
      _worktree_add "$@"
      ;;
    cd)
      _worktree_cd "$@"
      ;;
    list|ls)
      _worktree_list "$@"
      ;;
    prune)
      _worktree_prune "$@"
      ;;
    remove|rm)
      _worktree_remove "$@"
      ;;
    "")
      _worktree_interactive_cd
      ;;
    help|-h|--help)
      _worktree_usage
      ;;
    *)
      echo "unknown worktree command: $command" >&2
      _worktree_usage >&2
      return 1
      ;;
  esac
}

function wt() {
  worktree "$@"
}

# Bash completions
function _worktree_completion() {
  local cur prev commands branches
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="add cd list ls prune remove rm help"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
  else
    case "$prev" in
      add|cd|remove|rm)
        branches="$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
        ;;
    esac
  fi
}

complete -F _worktree_completion worktree
complete -F _worktree_completion wt

# True when the current directory is a linked worktree (not the main checkout).
function _lfg_in_worktree() {
  local git_dir common_dir

  git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1

  [ "$git_dir" != "$common_dir" ]
}

function _lfg_update() {
  local install_url install_dir install_script update_status

  if ! command -v curl >/dev/null 2>&1; then
    echo "lfg: curl is required to update" >&2
    return 1
  fi

  install_url="https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh"
  install_dir="$__lfg_dir"

  install_script="$(mktemp "${TMPDIR:-/tmp}/lfg-install.XXXXXX")" || return 1
  if ! curl -fsSL "$install_url" -o "$install_script"; then
    rm -f "$install_script"
    return 1
  fi

  bash "$install_script" --install-shell bash --install-dir "$install_dir"
  update_status=$?

  rm -f "$install_script"
  return "$update_status"
}

function _lfg_usage() {
  echo "usage: lfg [entrypoint]     (navigate to a worktree and start entrypoint, e.g. codex)"
  echo "       lfg --update         (update the lfg plugin to latest)"
  echo "       lfg --help           (show this help)"
}

function _lfg_completions_file() {
  if [ -n "${LFG_COMPLETIONS_FILE:-}" ]; then
    echo "$LFG_COMPLETIONS_FILE"
  else
    echo "$__lfg_dir/completions/lfg.entrypoints"
  fi
}

function _lfg_file_entrypoint_completions() {
  local completions_file

  completions_file="$(_lfg_completions_file)" || return 1
  [ -n "$completions_file" ] || return 1
  [ -r "$completions_file" ] || return 1

  awk 'NF && $1 !~ /^#/ { print $1 }' "$completions_file"
}

function _lfg_entrypoint_completions() {
  _lfg_file_entrypoint_completions
}

function lfg() {
  local entrypoint branch repo

  if [ "$#" -gt 1 ]; then
    _lfg_usage >&2
    return 1
  fi

  if [ "${1:-}" = "--update" ]; then
    _lfg_update
    return
  fi

  if [ "${1:-}" = "--help" ]; then
    _lfg_usage
    return
  fi

  entrypoint="${1:-${LFG_DEFAULT_AGENT_COMMAND:-claude}}"
  branch=""

  if ! command -v "$entrypoint" >/dev/null 2>&1; then
    echo "lfg: entrypoint not found on PATH: $entrypoint" >&2
    return 1
  fi

  # Already in a worktree: just launch here.
  if [ -z "$branch" ] && _lfg_in_worktree; then
    "$entrypoint"
    return
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo="$(_worktree_pick_repo)" || return 1
    cd "$repo" || return 1
  fi

  if [ -z "$branch" ]; then
    branch="$(_worktree_pick_branch)" || return 1
  fi

  _worktree_add "$branch" || return 1

  "$entrypoint"
}

function _lfg_completion() {
  local cur entrypoint_completions
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  case "$COMP_CWORD" in
    1)
      entrypoint_completions="$(_lfg_entrypoint_completions)"
      COMPREPLY=( $(compgen -W "--update --help $entrypoint_completions" -- "$cur") )
      ;;
  esac
}

complete -F _lfg_completion lfg
