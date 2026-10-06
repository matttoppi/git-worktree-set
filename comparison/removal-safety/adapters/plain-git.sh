# Reference: plain Git with no tool. One `git worktree add` per repository, then
# `git worktree remove` (no --force) and `git branch -d` for each repository.
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
  local name=$1 worktree repository
  for worktree in "$ROOT/.worktrees/$name"/*/; do
    repository=$(basename "$worktree")
    git -C "$ROOT/$repository" worktree remove "$worktree" && git -C "$ROOT/$repository" branch -d "$name"
  done
  rmdir "$ROOT/.worktrees/$name"
}
