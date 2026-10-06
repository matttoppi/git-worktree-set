# Adapter for git-worktree-manager. Layout: <root>.worktrees/<name>/<repository>,
# a sibling of the root. `worktree create` makes a worktree of every repository
# in the root on branch <name>. `worktree cleanup <name>` asks "Delete task?"
# on stdin; the harness answers y. No --force and no --delete-branches.
adapter_setup() { :; }
adapter_create() { worktree create "$1"; }
adapter_path() { printf '%s.worktrees/%s/%s' "$ROOT" "$1" "$2"; }
adapter_dir() { printf '%s.worktrees/%s' "$ROOT" "$1"; }
adapter_remove() { worktree cleanup "$1"; }
# `cleanup --merged` selects a task only if `git branch --merged
# origin/<default>` lists the branch of each repository. It has no age or done
# condition, so the adapter runs it as is.
adapter_cleanup_merged() { worktree cleanup --merged; }
