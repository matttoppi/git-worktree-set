# Control: deletes the workspace with no checks. It must lose work in each
# scenario; if it does not, a scenario does not test what it claims.
adapter_setup() { :; }
adapter_create() {
  local name=$1 repository
  shift
  for repository in "$@"; do
    git -C "$ROOT/$repository" worktree add -q -b "$name" "$ROOT/.worktrees/$name/$repository" || return
  done
}
adapter_path() { printf '%s/.worktrees/%s/%s' "$ROOT" "$1" "$2"; }
adapter_dir() { printf '%s/.worktrees/%s' "$ROOT" "$1"; }
adapter_remove() {
  local repository
  rm -rf "$ROOT/.worktrees/$1"
  for repository in api web; do
    git -C "$ROOT/$repository" worktree prune
    git -C "$ROOT/$repository" branch -D "$1"
  done
}
adapter_cleanup_merged() { adapter_remove "$1"; }
