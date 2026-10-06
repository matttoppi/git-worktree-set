# Adapter for git-worktree-set. Layout: <root>/.worktrees/<name>/<repository>.
adapter_setup() { :; }
adapter_create() { git worktree-set new "$@" >/dev/null; }
adapter_path() { printf '%s/.worktrees/%s/%s' "$ROOT" "$1" "$2"; }
adapter_dir() { printf '%s/.worktrees/%s' "$ROOT" "$1"; }
adapter_remove() { git worktree-set remove "$1"; }
adapter_cleanup_merged() {
  # remove --merged keeps a set that had activity in the last day, so make
  # the set idle first. The check under test is the one for lost work.
  local set_directory worktree git_directory
  set_directory=$(adapter_dir "$1")
  touch -t 202001010000 "$set_directory"
  for worktree in "$set_directory"/*/; do
    git_directory=$(git -C "$worktree" rev-parse --absolute-git-dir)
    touch -c -t 202001010000 "$git_directory/index" "$git_directory/logs/HEAD"
  done
  git worktree-set remove --merged
}
